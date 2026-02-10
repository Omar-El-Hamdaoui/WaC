$MyLocalvar ="This is a local variable "
$Script:MyScriptVar = "This is a script variable "

function Test-Scopes {
    $MyLocalvar ="Changed local variable "
    $Script:MyScriptVar = "Changed script variable "
}

Test-Scopes
$MyLocalvar
$Script:MyScriptVar