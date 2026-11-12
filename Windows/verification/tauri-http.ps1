param([Parameter(Mandatory)][string]$SessionFile)
$ErrorActionPreference = 'Stop'
$url = (Get-Content -Raw $SessionFile).Trim()
$script:checks = 0
function Assert($condition, [string]$message) { if (!$condition) { throw $message }; $script:checks++; Write-Output "PASS $message" }
function Rpc([string]$method, $parameters) {
    $body = @{jsonrpc='2.0';id=1;method=$method;params=$parameters} | ConvertTo-Json -Depth 30 -Compress
    # Deliberately suppress request/exception details: the URL carries authentication.
    try { Invoke-RestMethod -Uri $url -NoProxy -TimeoutSec 15 -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'none' }
        $category = $_.Exception.HttpRequestError
        $innerType = if ($_.Exception.InnerException) { $_.Exception.InnerException.GetType().Name } else { 'none' }
        throw "Authenticated MCP HTTP request failed: $($_.Exception.GetType().Name), HTTP $status, category $category, inner $innerType"
    }
}
function Call([string]$name, $arguments = @{}) {
    $response = Rpc 'tools/call' @{name=$name;arguments=$arguments}
    if ($response.error) { throw "RPC error for $name : $($response.error.code)" }
    $response.result.content[0].text | ConvertFrom-Json
}
function Fails([string]$name, $arguments, [string]$error) {
    $response = Rpc 'tools/call' @{name=$name;arguments=$arguments}
    $payload = $response.result.content[0].text | ConvertFrom-Json
    Assert ($response.result.isError -eq $true -and $payload.error -eq $error) "$name reports $error"
}
function State { $snapshot = Call 'get_elements'; ($snapshot.elements | Where-Object domId -eq 'state').text | ConvertFrom-Json }
$tools = (Rpc 'tools/list' @{}).result.tools.name
Assert ($tools -contains 'get_elements' -and $tools -notcontains 'screenshot' -and $tools -notcontains 'scroll') 'only implemented Tauri tools advertised'
Assert ((Call 'launch_context').platform -eq 'Windows') 'launch metadata identifies Windows'
Assert ((Call 'device_info').platform -eq 'Windows') 'device metadata identifies Windows'
Assert ((Call 'list_windows').windows.id -contains 'main_test') 'runtime window is listed'
Assert ((Call 'focus_window' @{window_id='main_test'}).success -eq $true) 'runtime window focused'
Assert ((Call 'get_menu_bar').count -ge 0) 'runtime menu inspected'
Assert ((Call 'get_dom_interactive').count -gt 0) 'DOM inventory alias works'
$snapshot = Call 'get_elements'
$counter = ($snapshot.elements | Where-Object domId -eq 'counter').id
Assert ($counter -like 'web.main_test.*') 'window labels produce usable IDs'
Assert (($snapshot.elements | Where-Object domId -eq 'password').value -eq $null) 'password value excluded'
Call 'tap_element' @{id=$counter} | Out-Null
Assert ((State).clicks -eq 1) 'ID tap changed app state'
Call 'tap_text' @{text='button'} | Out-Null
Assert ((State).literalClicks -eq 1 -and (State).clicks -eq 1) 'tap_text does not interpret text as CSS'
Call 'tap_element' @{id='insert'} | Out-Null
Assert (((Call 'get_elements').elements | Where-Object label -eq 'Inserted').selector.Length -gt 0) 'elements without DOM IDs retain CSS selectors'
Call 'tap_element' @{id=$counter} | Out-Null
Assert ((State).clicks -eq 2) 'old ID stays on same element after DOM insertion'
$unicode = "Žluťoučký 🦕 東京 `"quote`""
Call 'type_text' @{id='edit';text=$unicode} | Out-Null
Assert ((State).text -eq $unicode) 'Unicode and quotes reach real WebView input'
Call 'clear_text' @{id='edit'} | Out-Null
Assert ((State).text -eq '') 'clear changes real input state'
Call 'type_text' @{id='edit';text='   '} | Out-Null
Assert ((State).text -eq '   ') 'whitespace text is valid input'
Call 'type_text' @{id='rich';text=$unicode} | Out-Null
Assert ((State).rich -eq $unicode) 'contenteditable receives input'
Call 'type_text' @{id='select';text='two'} | Out-Null
Assert ((State).choice -eq 'two') 'select uses exact option value'
Call 'tap_element' @{id='checkbox'} | Out-Null
Assert ((State).checked -eq $true) 'checkbox default activation changes state'
Fails 'tap_element' @{id='disabled'} 'target_disabled'
Fails 'type_text' @{id='inherited-disabled';text='bad'} 'target_disabled'
Fails 'type_text' @{id='readonly';text='bad'} 'target_not_editable'
Fails 'type_text' @{id='counter';text='bad'} 'target_not_editable'
Fails 'type_text' @{id='select';text='absent'} 'option_not_found'
Fails 'tap_element' @{id='missing'} 'target_not_found'
Fails 'tap_point' @{x=-100000;y=-100000} 'point_outside_window'
Fails 'get_elements' @{window_id='missing'} 'window_not_found'
$batch = Call 'batch' @{stop_on_error=$true;actions=@(@{tool='tap_element';arguments=@{id='disabled'}},@{tool='tap_element';arguments=@{id=$counter}})}
Assert ($batch.success -eq $false -and $batch.results.Count -eq 1) 'batch stops on DOM failure'
Call 'tap_element' @{id=$counter} | Out-Null
Assert ((State).clicks -eq 3) 'WebView recovers after rejected actions'
Call 'tap_element' @{id='detach'} | Out-Null
Assert (-not ((Call 'get_elements').elements | Where-Object domId -eq 'counter')) 'detached node is absent from inventory'
Call 'tap_element' @{id='reattach'} | Out-Null
Assert (((Call 'get_elements').elements | Where-Object domId -eq 'counter').id -eq $counter) 'reinserted node retains its original ID'
Call 'tap_element' @{id=$counter} | Out-Null
Assert ((State).clicks -eq 4) 'reinserted node ID still activates the same control'
$snapshot = Call 'get_elements'
$rect = ($snapshot.elements | Where-Object domId -eq 'counter').rect
Call 'tap_point' @{x=($rect.x+$rect.width/2);y=($rect.y+$rect.height/2)} | Out-Null
Assert ((State).clicks -eq 5) 'screen point from inventory taps expected control'
Write-Output "PASS $script:checks real Tauri WebView/MCP checks"
