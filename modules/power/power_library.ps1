#Requires -Version 5.1
# https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options#option_hibernate
function Read-SetupHibernateState {
 $key=Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction Stop
 $names=@($key.GetValueNames())
 # Windows may only write HibernateEnabledDefault until hibernation is changed explicitly.
 $name=if('HibernateEnabled' -in $names){'HibernateEnabled'}elseif('HibernateEnabledDefault' -in $names){'HibernateEnabledDefault'}else{''}
 $kind='';$value=$null
 if($name){$kind=[string]$key.GetValueKind($name);$value=$key.GetValue($name)}
 $hiberFile=Join-Path ($env:SystemDrive+'\') 'hiberfil.sys'
 [pscustomobject]@{Source=$name;Kind=$kind;HibernateEnabled=$value;HiberFile=$hiberFile;HiberFilePresent=[bool](Test-Path -LiteralPath $hiberFile -PathType Leaf)}
}
function Test-SetupHibernateDisabled {
 param([Parameter(Mandatory=$true)]$State)
 $State.Kind -eq 'DWord' -and $State.HibernateEnabled -eq 0 -and -not $State.HiberFilePresent
}
function Disable-SetupHibernate {
 & powercfg.exe /hibernate off
 if($LASTEXITCODE -ne 0){throw ('停用休眠失敗；powercfg 退出碼：'+$LASTEXITCODE)}
 $state=Read-SetupHibernateState
 if(-not (Test-SetupHibernateDisabled $state)){throw ('休眠讀回仍未停用（'+$state.Source+'='+$state.HibernateEnabled+'；休眠檔存在：'+$state.HiberFilePresent+'），可能被組織政策覆寫。')}
 return $state
}
