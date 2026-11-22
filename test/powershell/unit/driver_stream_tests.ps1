#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_stream_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Fails([scriptblock]$Action){try{& $Action;return $false}catch{return $true}}
$payload=[Text.Encoding]::UTF8.GetBytes('owned inert HTTP fixture');$sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-','')}finally{$sha.Dispose()}
Add-Type -TypeDefinition @'
using System; using System.Net; using System.Net.Sockets; using System.Text; using System.Threading;
public sealed class Issue185Server : IDisposable {
 readonly TcpListener listener; readonly Thread thread; readonly byte[] body; public int Port; public volatile bool Accepted;
 public Issue185Server(byte[] value){body=value;listener=new TcpListener(IPAddress.Loopback,0);listener.Start();Port=((IPEndPoint)listener.LocalEndpoint).Port;thread=new Thread(Serve);thread.IsBackground=true;thread.Start();}
 void Serve(){try{using(var c=listener.AcceptTcpClient())using(var s=c.GetStream()){Accepted=true;s.ReadTimeout=5000;int state=0;while(state<4){int x=s.ReadByte();if(x<0)return;state=(state==0&&x==13)?1:(state==1&&x==10)?2:(state==2&&x==13)?3:(state==3&&x==10)?4:0;}byte[] h=Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: "+body.Length+"\r\nConnection: close\r\n\r\n");s.Write(h,0,h.Length);s.Write(body,0,body.Length);s.Flush();c.Client.Shutdown(SocketShutdown.Send);Thread.Sleep(200);}}catch(Exception){} }
 public void Dispose(){listener.Stop();thread.Join(6000);}
}
public sealed class Issue185BoundedInput : System.IO.MemoryStream {
 public int Largest;
 public Issue185BoundedInput(byte[] b):base(b){}
 public override int Read(byte[] b,int offset,int count){if(count>Largest)Largest=count;return base.Read(b,offset,count);}
}
'@
Assert (Test-SetupDriverStreamCapacity -SizeBytes ([long]4294967295) -AvailableBytes ([long]4294967295) -FileSystem FAT32) 'FAT32 maximum accepted'
Assert (-not (Test-SetupDriverStreamCapacity -SizeBytes ([long]4294967296) -AvailableBytes ([long]4294967296) -FileSystem FAT32)) 'FAT32 4 GiB rejected'
Assert (Test-SetupDriverStreamCapacity -SizeBytes ([long]4294967297) -AvailableBytes ([long]4294967297) -FileSystem NTFS) '64-bit size accepted'
Assert (-not (Test-SetupDriverStreamCapacity -SizeBytes 11 -AvailableBytes 10 -FileSystem NTFS)) 'insufficient space rejected'
function Transfer([byte[]]$Bytes,[long]$Expected,[string]$Digest){$inputStream=New-Object IO.MemoryStream(,$Bytes);$output=New-Object IO.MemoryStream;try{$r=Copy-SetupDriverVerifiedStream -InputStream $inputStream -OutputStream $output -SizeBytes $Expected -SHA256 $Digest;return $r}finally{$inputStream.Dispose();$output.Dispose()}}
$r=Transfer $payload $payload.Length $hash;Assert ($r.SizeBytes -eq $payload.Length -and $r.SHA256 -ceq $hash.ToLowerInvariant()) 'stream and incremental digest verified'
$bounded=New-Object Issue185BoundedInput(,$payload);$sink=New-Object IO.MemoryStream
try{$null=Copy-SetupDriverVerifiedStream -InputStream $bounded -OutputStream $sink -SizeBytes $payload.Length -SHA256 $hash;Assert ($bounded.Largest -eq 65536) 'read buffer is bounded'}finally{$bounded.Dispose();$sink.Dispose()}
Assert (Fails {Transfer $payload ($payload.Length+1) $hash}) 'truncation rejected'
Assert (Fails {Transfer $payload ($payload.Length-1) $hash}) 'overrun rejected'
Assert (Fails {Transfer $payload $payload.Length ('0'*64)}) 'digest mismatch rejected'
$server=New-Object Issue185Server(,$payload);$sink=New-Object IO.MemoryStream;$message=''
try{try{Invoke-SetupDriverHttpStream -Uri ('http://127.0.0.1:'+ $server.Port +'/inert') -OutputStream $sink -SizeBytes $payload.Length -SHA256 $hash -Capacity ([pscustomobject]@{AvailableBytes=[long]0;FileSystem='NTFS'})}catch{$message=$_.Exception.Message};Start-Sleep -Milliseconds 100;Assert ($message -ceq 'Destination capacity is insufficient or invalid.' -and -not $server.Accepted -and $sink.Length -eq 0) 'capacity rejection precedes HTTP and write'}finally{$server.Dispose();$sink.Dispose()}
foreach($invalid in @([pscustomobject]@{AvailableBytes='999';FileSystem='NTFS'},[pscustomobject]@{AvailableBytes=[long]999;FileSystem='unknown'},[pscustomobject]@{AvailableBytes=[long]4294967296;FileSystem='FAT32'})){
 $sink=New-Object IO.MemoryStream;$message='';$size=if($invalid.FileSystem -eq 'FAT32'){[long]4294967296}else{[long]$payload.Length}
 try{try{Invoke-SetupDriverHttpStream -Uri 'http://127.0.0.1:1/' -OutputStream $sink -SizeBytes $size -SHA256 $hash -Capacity $invalid}catch{$message=$_.Exception.Message};Assert ($message -ceq 'Destination capacity is insufficient or invalid.' -and $sink.Length -eq 0) 'invalid capacity rejected before request'}finally{$sink.Dispose()}
}
$cap=[pscustomobject]@{AvailableBytes=[long]100000;FileSystem='NTFS'}
$server=New-Object Issue185Server(,$payload);$sink=New-Object IO.MemoryStream
try{$r=Invoke-SetupDriverHttpStream -Uri ('http://127.0.0.1:'+ $server.Port +'/inert') -OutputStream $sink -SizeBytes $payload.Length -SHA256 $hash -Capacity $cap;Assert ($r.SizeBytes -eq $payload.Length -and [Text.Encoding]::UTF8.GetString($sink.ToArray()) -ceq 'owned inert HTTP fixture') 'owned loopback HTTP stream verified'}finally{$server.Dispose();$sink.Dispose()}
$stale=New-Object IO.MemoryStream; $stale.WriteByte(42)
try{Assert (Fails {Invoke-SetupDriverHttpStream -Uri 'http://127.0.0.1:1/' -OutputStream $stale -SizeBytes $payload.Length -SHA256 $hash -Capacity $cap}) 'nonempty caller stream rejected';Assert ($stale.Length -eq 1 -and $stale.ToArray()[0] -eq 42 -and $stale.CanWrite) 'foreign content and caller ownership preserved'}finally{$stale.Dispose()}
$server=New-Object Issue185Server(,$payload);$sink=New-Object IO.MemoryStream
try{Assert (Fails {Invoke-SetupDriverHttpStream -Uri ('http://127.0.0.1:'+ $server.Port +'/inert') -OutputStream $sink -SizeBytes $payload.Length -SHA256 ('0'*64) -Capacity $cap}) 'corrupt content rejected';Assert ($sink.CanWrite -and $sink.Length -eq $payload.Length) 'failure retains caller-owned unverified stream'}finally{$server.Dispose();$sink.Dispose()}
foreach($bad in @('relative','file:///tmp/a','https://user@example.invalid/a',"https://example.invalid/`n")){ $sink=New-Object IO.MemoryStream;try{Assert (Fails {Invoke-SetupDriverHttpStream -Uri $bad -OutputStream $sink -SizeBytes $payload.Length -SHA256 $hash -Capacity $cap}) 'unsafe URI rejected'}finally{$sink.Dispose()} }
