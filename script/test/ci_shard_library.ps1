#Requires -Version 5.1
# PR 階段把完整 suite 清單依實測耗時平衡切成互不重疊的分片；聯集必等於完整清單。
function Get-CISuiteWeights {
 param([Parameter(Mandatory=$true)][string]$Path)
 if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw ('缺少 suite 權重檔：'+$Path)}
 $json=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false,$true)))
 $table=@{}
 foreach($property in $json.PSObject.Properties){
  $number=0.0
  if($property.Value -is [string] -or $property.Value -is [bool] -or $null -eq $property.Value -or -not [double]::TryParse([string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0}',$property.Value),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)){throw ('權重必須是數字：'+$property.Name)}
  if($number -lt 0){throw ('權重不可為負：'+$property.Name)}
  $table[$property.Name]=$number
 }
 return $table
}
function Select-CISuiteShard {
 param([Parameter(Mandatory=$true)][object[]]$Cases,[Parameter(Mandatory=$true)][int]$ShardIndex,[Parameter(Mandatory=$true)][int]$ShardCount,[hashtable]$Weights=@{},[double]$DefaultWeight=10)
 if($ShardCount -lt 1){throw '分片數必須至少為 1。'}
 if($ShardIndex -lt 0 -or $ShardIndex -ge $ShardCount){throw '分片索引超出分片範圍。'}
 if(-not $Cases.Count){throw '沒有 suite 可分派，不得回報成功。'}
 $names=@($Cases|ForEach-Object {[string]$_.Name})
 if(@($names|Select-Object -Unique).Count -ne $names.Count){throw 'suite 名稱重複，分派可能靜默漏跑。'}
 $loads=New-Object 'double[]' $ShardCount
 $mine=New-Object Collections.Generic.List[object]
 # 最長者先放入目前負載最輕的分片；同權重與同負載以名稱序決定，結果與輸入順序無關。
 $ordered=@($Cases|ForEach-Object {[pscustomobject]@{Case=$_;Name=[string]$_.Name;Weight=$(if($Weights.ContainsKey([string]$_.Name)){[double]$Weights[[string]$_.Name]}else{$DefaultWeight})}}|Sort-Object @{Expression='Weight';Descending=$true},@{Expression='Name';Ascending=$true})
 foreach($item in $ordered){
  $target=0
  for($slot=1;$slot -lt $ShardCount;$slot++){if($loads[$slot] -lt $loads[$target]){$target=$slot}}
  $loads[$target]+=$item.Weight
  if($target -eq $ShardIndex){$mine.Add($item.Case)}
 }
 return @($mine.ToArray()|Sort-Object {[string]$_.Name})
}
