#Requires -Version 5.1
# https://learn.microsoft.com/en-us/windows/win32/secauthn/protecting-the-automatic-logon-password
function Invoke-SetupLsaSecret {
 param([string]$Name,[Parameter(Mandatory=$true)][ValidateSet('Query','Remove')][string]$Action)
 if([string]::IsNullOrWhiteSpace($Name)){throw 'LSA機密名稱不可空白。'}
 if(-not ('WindowsSetup.AutologonLsa' -as [type])){Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;namespace WindowsSetup{public static class AutologonLsa{[StructLayout(LayoutKind.Sequential)]public struct UnicodeString{public ushort Length;public ushort MaximumLength;public IntPtr Buffer;}[StructLayout(LayoutKind.Sequential)]public struct ObjectAttributes{public int Length;public IntPtr RootDirectory;public IntPtr ObjectName;public uint Attributes;public IntPtr SecurityDescriptor;public IntPtr SecurityQualityOfService;}[DllImport("advapi32.dll")]public static extern uint LsaOpenPolicy(IntPtr systemName,ref ObjectAttributes attributes,uint access,out IntPtr policy);[DllImport("advapi32.dll")]public static extern uint LsaRetrievePrivateData(IntPtr policy,ref UnicodeString key,out IntPtr data);[DllImport("advapi32.dll")]public static extern uint LsaStorePrivateData(IntPtr policy,ref UnicodeString key,IntPtr data);[DllImport("advapi32.dll")]public static extern uint LsaFreeMemory(IntPtr buffer);[DllImport("advapi32.dll")]public static extern uint LsaClose(IntPtr policy);[DllImport("advapi32.dll")]public static extern int LsaNtStatusToWinError(uint status);}}' -ErrorAction Stop}
 $attributes=New-Object 'WindowsSetup.AutologonLsa+ObjectAttributes';$attributes.Length=[Runtime.InteropServices.Marshal]::SizeOf($attributes)
 $policy=[IntPtr]::Zero
 # POLICY_GET_PRIVATE_INFORMATION (0x4) | POLICY_CREATE_SECRET (0x20)
 $status=[WindowsSetup.AutologonLsa]::LsaOpenPolicy([IntPtr]::Zero,[ref]$attributes,[uint32]0x24,[ref]$policy)
 if($status -ne 0){throw ('無法開啟LSA原則（Win32錯誤 '+[WindowsSetup.AutologonLsa]::LsaNtStatusToWinError($status)+'）；請以系統管理員執行。')}
 $key=New-Object 'WindowsSetup.AutologonLsa+UnicodeString';$key.Length=[uint16]($Name.Length*2);$key.MaximumLength=[uint16]($Name.Length*2+2)
 $key.Buffer=[Runtime.InteropServices.Marshal]::StringToHGlobalUni($Name)
 try{
  if($Action -eq 'Remove'){$status=[WindowsSetup.AutologonLsa]::LsaStorePrivateData($policy,[ref]$key,[IntPtr]::Zero)}
  else{
   # The secret buffer is released without being read, copied or logged.
   $data=[IntPtr]::Zero;$status=[WindowsSetup.AutologonLsa]::LsaRetrievePrivateData($policy,[ref]$key,[ref]$data)
   if($data -ne [IntPtr]::Zero){[void][WindowsSetup.AutologonLsa]::LsaFreeMemory($data)}
  }
 }finally{[Runtime.InteropServices.Marshal]::FreeHGlobal($key.Buffer);[void][WindowsSetup.AutologonLsa]::LsaClose($policy)}
 if($status -eq 0){return $true}
 # STATUS_OBJECT_NAME_NOT_FOUND
 if($status -eq [uint32]3221225524){return $false}
 throw ('LSA機密'+$(if($Action -eq 'Remove'){'刪除'}else{'查詢'})+'失敗（Win32錯誤 '+[WindowsSetup.AutologonLsa]::LsaNtStatusToWinError($status)+'）。')
}
function Assert-SetupAutologonPlainPath {
 param([string]$Path)
 $full=[IO.Path]::GetFullPath($Path);$cursor=$full
 while($cursor){
  if(Test-Path -LiteralPath $cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '自動登入紀錄路徑不可使用重新解析點。'}}
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
 return $full
}
function Read-SetupWinlogonValue {
 param([string]$Name)
 $key=Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop
 $exists=$Name -in @($key.GetValueNames())
 $kind='';$value=$null
 if($exists){$kind=[string]$key.GetValueKind($Name);$value=$key.GetValue($Name)}
 [pscustomobject]@{Exists=$exists;Kind=$kind;Value=$value}
}
function Get-SetupAutologonState {
 $auto=Read-SetupWinlogonValue AutoAdminLogon
 $plain=(Read-SetupWinlogonValue DefaultPassword).Exists
 $secret=Invoke-SetupLsaSecret -Name DefaultPassword -Action Query
 [pscustomobject]@{AutoAdminLogon=$(if($auto.Exists){[string]$auto.Value}else{$null});PlainPasswordPresent=$plain;LsaSecretPresent=$secret;Disabled=($auto.Exists -and $auto.Kind -eq 'String' -and [string]$auto.Value -ceq '0' -and -not $plain -and -not $secret)}
}
function Invoke-SetupAutologonRestore {
 param([Parameter(Mandatory=$true)][string]$ReportPath,[Parameter(Mandatory=$true)][string]$UserSid,[string]$Computer=$env:COMPUTERNAME)
 $ErrorActionPreference='Stop'
 $ReportPath=Assert-SetupAutologonPlainPath $ReportPath
 $success=$false;$errorText='';$state=$null
 try{
  $path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  New-ItemProperty -LiteralPath $path -Name AutoAdminLogon -Value '0' -PropertyType String -Force -ErrorAction Stop|Out-Null
  if((Read-SetupWinlogonValue DefaultPassword).Exists){Remove-ItemProperty -LiteralPath $path -Name DefaultPassword -ErrorAction Stop}
  if(Invoke-SetupLsaSecret -Name DefaultPassword -Action Query){[void](Invoke-SetupLsaSecret -Name DefaultPassword -Action Remove)}
  $state=Get-SetupAutologonState
  $success=$state.Disabled
  if(-not $success){throw '自動登入停用讀回不符合要求，可能被組織政策或其他工具覆寫。'}
 }catch{$success=$false;$errorText=$_.Exception.Message}
 $result=[ordered]@{Success=$success;Mode='Restore';UserSID=$UserSid;Computer=$Computer;CheckedAt=(Get-Date).ToString('o');Error=$errorText;AutoAdminLogon=$state.AutoAdminLogon;PlainPasswordPresent=$state.PlainPasswordPresent;LsaSecretPresent=$state.LsaSecretPresent;Scope='停用此電腦自動登入並清除儲存的密碼；保留 DefaultUserName 與 DefaultDomainName；實際不再自動登入需重新開機確認。'}
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ReportPath));[IO.File]::WriteAllText($ReportPath,($result|ConvertTo-Json),(New-Object Text.UTF8Encoding($true)))
 if(-not $success){throw $errorText}
 [pscustomobject]$result
}
function Invoke-CurrentUserAutologonRestore {
 $root=Join-Path $env:ProgramData 'NUC8-Setup'
 Invoke-SetupAutologonRestore -ReportPath (Join-Path $root 'Autologon-Result.json') -UserSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
}
