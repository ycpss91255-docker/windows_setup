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
