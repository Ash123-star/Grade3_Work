$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$settings = @{}
foreach ($line in Get-Content -Encoding UTF8 (Join-Path $repoRoot 'deploy/backend/.env')) {
    if ($line -match '^([A-Z][A-Z0-9_]*)=(.*)$') {
        $settings[$Matches[1]] = $Matches[2].Trim('"', "'")
    }
}
$apiKey = $settings['DEEPSEEK_API_KEY']
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'DeepSeek 密钥未配置' }
$baseUrl = $settings['DEEPSEEK_BASE_URL']
if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = 'https://api.deepseek.com' }
$model = $settings['DEEPSEEK_MODEL']
if ([string]::IsNullOrWhiteSpace($model)) { $model = 'deepseek-chat' }

$sourceOne = @{ id = 'S1'; text = '星桥结算协议完成接口评审。'; claimType = 'FACT' }
$sourceTwo = @{ id = 'S2'; text = '跨线需求澄清复盘记录了返工原因。'; claimType = 'FACT' }
$cases = @(
    @{ mode = 'current-input'; goal = '发展技术架构设计能力'; sources = @(); paths = @(); correction = '' },
    @{ mode = 'text-rag'; goal = '发展技术架构设计能力'; sources = @($sourceOne); paths = @(); correction = '' },
    @{ mode = 'text-graph-rag'; goal = '发展技术架构设计能力'; sources = @($sourceOne, $sourceTwo); paths = @(@{ from = 'S1'; to = 'S2'; relation = '复盘补证' }); correction = '' },
    @{ mode = 'corrected-goal'; goal = '发展跨部门协作负责人能力'; sources = @($sourceOne, $sourceTwo); paths = @(@{ from = 'S1'; to = 'S2'; relation = '复盘补证' }); correction = '本人已把目标从技术架构调整为跨部门协作。' }
)
$system = '你是发展分析助手。只能基于输入证据描述已发生的事；没有证据时说明信息不足。所有方向只是待验证推测。返回 JSON：{"summary":"文本","directions":[{"text":"方向","sourceIds":["S1"],"conditions":["前提"]}],"gaps":["缺口"]}。每个方向的 sourceIds 仅能来自输入来源。不要预测成功概率或编造已获得的成果。'
$results = @()
foreach ($case in $cases) {
    $inputData = @{ goal = $case.goal; sources = $case.sources; paths = $case.paths; correction = $case.correction }
    $requestData = @{ model = $model; stream = $false; max_tokens = 450; response_format = @{ type = 'json_object' }; messages = @(@{ role = 'system'; content = $system }, @{ role = 'user'; content = ($inputData | ConvertTo-Json -Depth 12 -Compress) }) }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $requestBytes = [Text.Encoding]::UTF8.GetBytes(($requestData | ConvertTo-Json -Depth 12 -Compress))
        $webReply = Invoke-WebRequest -UseBasicParsing -Method Post -Uri ($baseUrl.TrimEnd('/') + '/chat/completions') -Headers @{ Authorization = "Bearer $apiKey" } -ContentType 'application/json; charset=utf-8' -Body $requestBytes -TimeoutSec 45
        $responseBuffer = New-Object IO.MemoryStream
        $webReply.RawContentStream.CopyTo($responseBuffer)
        $reply = [Text.Encoding]::UTF8.GetString($responseBuffer.ToArray()) | ConvertFrom-Json
    } catch {
        throw "DeepSeek 评估请求失败：$($case.mode)"
    } finally {
        $watch.Stop()
    }
    $output = $reply.choices[0].message.content | ConvertFrom-Json
    $allowed = @($case.sources | ForEach-Object { $_.id })
    $references = @($output.directions | ForEach-Object { $_.sourceIds } | Where-Object { $_ })
    $validReferences = @($references | Where-Object { $allowed -contains $_ }).Count
    $results += [pscustomobject]@{
        mode = $case.mode
        goal = $case.goal
        sourceIds = $allowed
        latencyMs = $watch.ElapsedMilliseconds
        inputTokens = $reply.usage.prompt_tokens
        outputTokens = $reply.usage.completion_tokens
        totalTokens = $reply.usage.total_tokens
        citations = $references.Count
        validCitations = $validReferences
        output = $output
    }
}
$destination = Join-Path $repoRoot 'docs/ai-map-four-way-evaluation.json'
$results | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $destination
Write-Host '四组 DeepSeek 合成证据评估已写入 docs/ai-map-four-way-evaluation.json'
