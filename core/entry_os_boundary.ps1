#Requires -Version 5.1
function Get-SetupEntryIdentity { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Test-SetupEntryAdministrator {
 $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
 return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Start-SetupEntryElevated {
 param([string]$Command,[switch]$UseSystemPowerShell)
 $executable=if($UseSystemPowerShell){Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe'}else{'powershell.exe'}
 Start-Process $executable -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command)))
}
function Get-SetupEntryUserUILanguage {
 # Reads the target user's own language setting, never the calling process culture (SSH or session 0 may differ).
 param([string]$UserSid=(Get-SetupEntryIdentity),[string]$RegistryRoot='Registry::HKEY_USERS')
 $desktop=$RegistryRoot+'\'+$UserSid+'\Control Panel\Desktop'
 $sources=@(@{Path=$desktop;Name='PreferredUILanguages'},@{Path=$desktop+'\MuiCached';Name='MachinePreferredUILanguages'})
 if($UserSid -in @('S-1-5-18','S-1-5-19','S-1-5-20')){return [pscustomobject]@{Name='';Source='目標使用者登錄';Reason=('目前身分為系統帳號 '+$UserSid+'，沒有明確目標使用者 SID，無法判斷其語言')}}
 $reasons=@()
 foreach($source in $sources){
  try{
   $item=Get-ItemProperty -LiteralPath $source.Path -ErrorAction Stop
   $value=@($item.($source.Name))|Where-Object {-not [string]::IsNullOrWhiteSpace($_)}|Select-Object -First 1
   if($value){return [pscustomobject]@{Name=[string]$value;Source=('目標使用者登錄 '+$source.Name);Reason=''}}
   $reasons+=($source.Name+' 無資料')
  }catch{$reasons+=($source.Name+' 無法讀取：'+$_.Exception.Message)}
 }
 [pscustomobject]@{Name='';Source='目標使用者登錄';Reason=('無法判斷目標使用者語言（'+($reasons -join '；')+'）')}
}
