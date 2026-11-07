# Instalador do Ocarina Recomp: uma janela, sem comandos. Instala o que faltar e compila o jogo a partir do arquivo da propria pessoa.
# Rodar de novo continua de onde parou. Testes: OCARINA_PASTA, OCARINA_JOGO e OCARINA_REPO evitam os dialogos e OCARINA_AUTO=1 inicia sozinho.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$REPO = if ($env:OCARINA_REPO) { $env:OCARINA_REPO } else { 'https://github.com/sostenesfreitas/ocarina-recomp' }
$RAMO = if ($env:OCARINA_RAMO) { $env:OCARINA_RAMO } else { 'main' }
$HASH_MAIN = 'F90499EEB596D67C730FAC9B7E247B3A46D51D6F334C767AEF071C9A783CCCEF'   # o main da versao 1.1.1, sem compressao
$ZBIC = '11b08f2712264bbed731545085cbd9702096ceb7'
$GB_NECESSARIOS = 60
$LOG = Join-Path $env:TEMP 'ocarina-instalador.log'
$MSYS = 'C:\msys64'
$VS = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer'
$TIGELA = [char]::ConvertFromUtf32(0x1F35C)

$PT = (Get-UICulture).TwoLetterISOLanguageName -eq 'pt'
function L($pt, $en) { if ($PT) { return $pt } return $en }

$script:cancelar = $false
$script:rodando = $false
$script:passoIni = [DateTime]::Now
$script:estimativa = 1
$script:feito = 0.0
$script:pesoAtual = 1.0
$script:proc = $null

$DICAS = @(
    (L 'Um miojo fica pronto em 3 minutos. Isto aqui leva um pouco mais.' 'Instant noodles take 3 minutes. This takes a little longer.'),
    (L 'Pode usar o PC enquanto instala, só vai ficar um pouco mais lento.' 'You can use your PC during the install, it will just be a little slower.'),
    (L 'Não precisa olhar: quando terminar, o botão Jogar aparece aqui.' 'No need to watch: the Play button shows up here when it is done.'),
    (L 'Se fechar ou faltar luz, é só abrir o instalador de novo: ele continua de onde parou.' 'If it closes or the power goes out, just open the installer again: it picks up where it stopped.'),
    (L 'O jogo não vem daqui: ele é montado no seu PC, a partir do seu próprio arquivo.' 'The game does not come from here: it is built on your PC from your own copy.'),
    (L 'Dá tempo de fazer uns vinte miojos. Com tempero, por favor.' 'There is time to cook about twenty bowls of noodles. Seasoning included, please.'),
    (L 'Na primeira vez jogando, áreas novas podem dar umas travadinhas. Depois melhora.' 'The first time you play, new areas may stutter a little. It gets better after that.')
)

# ---- a janela
function Rotulo($texto, $x, $y, $l, $a, $tam = 10, $negrito = $false) {
    $c = New-Object Windows.Forms.Label
    $c.Text = $texto; $c.Left = $x; $c.Top = $y; $c.Width = $l; $c.Height = $a
    $estilo = if ($negrito) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $c.Font = New-Object Drawing.Font('Segoe UI', $tam, $estilo)
    return $c
}
function Botao($texto, $x, $y, $l, $a = 36) {
    $c = New-Object Windows.Forms.Button
    $c.Text = $texto; $c.Left = $x; $c.Top = $y; $c.Width = $l; $c.Height = $a
    $c.Font = New-Object Drawing.Font('Segoe UI', 10)
    return $c
}

$form = New-Object Windows.Forms.Form
$form.Text = (L 'Ocarina Recomp - Instalador' 'Ocarina Recomp - Installer')
$form.ClientSize = New-Object Drawing.Size(640, 560)
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false; $form.StartPosition = 'CenterScreen'
$form.KeyPreview = $true

$titulo = Rotulo 'Ocarina Recomp' 24 16 590 40 20 $true
$sub = Rotulo (L 'Ocarina of Time nativo no Windows, sem emulador. Experimental.' 'Ocarina of Time running natively on Windows, no emulator. Experimental.') 26 56 590 24
$form.Controls.AddRange(@($titulo, $sub))

# Tela 1: escolher o jogo
$tela1 = New-Object Windows.Forms.Panel
$tela1.SetBounds(0, 86, 640, 430)
$t1a = Rotulo (L "O que este instalador faz:`n`n  1. Instala as ferramentas que faltarem (o Windows pode pedir permissão: clique em Sim).`n  2. Monta o jogo no seu PC a partir do SEU arquivo do jogo.`n  3. Cria um atalho na Área de Trabalho.`n`nLeva de 30 minutos a 2 horas, e você pode usar o PC enquanto isso." "What this installer does:`n`n  1. Installs any tools you are missing (Windows may ask for permission: click Yes).`n  2. Builds the game on your PC from YOUR copy of the game.`n  3. Creates a shortcut on your desktop.`n`nIt takes 30 minutes to 2 hours, and you can use your PC in the meantime.") 26 0 590 130
$t1b = Rotulo (L 'Passo 1: mostre onde está o seu jogo (versão 1.1.1)' 'Step 1: show where your game is (version 1.1.1)') 26 136 590 24 11 $true
$btArq = Botao (L 'Escolher arquivo .nup' 'Choose .nup file') 26 164 280
$btPasta = Botao (L 'Escolher pasta com exefs e romfs' 'Choose folder with exefs and romfs') 322 164 292
$lbJogo = Rotulo (L 'Nada escolhido ainda.' 'Nothing chosen yet.') 26 206 590 42
$t1c = Rotulo (L 'Passo 2: confira onde instalar' 'Step 2: check where to install') 26 252 590 24 11 $true
$lbPasta = Rotulo '' 26 280 440 24
$btTrocar = Botao (L 'Trocar pasta' 'Change folder') 482 274 132 32
$lbAviso = Rotulo '' 26 314 590 44
$lbAviso.ForeColor = [Drawing.Color]::DarkOrange
$btInstalar = Botao (L 'Instalar' 'Install') 214 366 212 48
$btInstalar.Font = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold)
$btInstalar.Enabled = $false
$tela1.Controls.AddRange(@($t1a, $t1b, $btArq, $btPasta, $lbJogo, $t1c, $lbPasta, $btTrocar, $lbAviso, $btInstalar))

# Tela 2: progresso
$tela2 = New-Object Windows.Forms.Panel
$tela2.SetBounds(0, 86, 640, 430)
$tela2.Visible = $false
$lista = New-Object Windows.Forms.ListBox
$lista.SetBounds(26, 0, 588, 210)
$lista.Font = New-Object Drawing.Font('Segoe UI', 10)
$lista.SelectionMode = 'None'
$barra = New-Object Windows.Forms.ProgressBar
$barra.SetBounds(26, 220, 588, 26)
$barra.Maximum = 1000
$lbPct = Rotulo '' 26 250 588 22 10 $true
$lbLinha = Rotulo '' 26 274 588 40 8
$lbLinha.ForeColor = [Drawing.Color]::Gray
$lbDica = Rotulo $DICAS[0] 26 318 588 44 10
$btJogar = Botao (L 'Jogar' 'Play') 150 370 160 44
$btJogar.Font = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold)
$btJogar.Visible = $false
$btFechar = Botao (L 'Fechar' 'Close') 330 370 160 44
$btFechar.Visible = $false
$tela2.Controls.AddRange(@($lista, $barra, $lbPct, $lbLinha, $lbDica, $btJogar, $btFechar))
$form.Controls.AddRange(@($tela1, $tela2))

$rodape = Rotulo (L "Feito com $TIGELA por Miojo" "Made with $TIGELA by Miojo") 24 526 300 26 9
$rodape.Font = New-Object Drawing.Font('Segoe UI Emoji', 9)
$rodape.Cursor = [Windows.Forms.Cursors]::Hand
$btLog = New-Object Windows.Forms.LinkLabel
$btLog.Text = (L 'Ver registro da instalação' 'View install log'); $btLog.SetBounds(446, 528, 180, 22); $btLog.TextAlign = 'MiddleRight'
$form.Controls.AddRange(@($rodape, $btLog))
$btLog.add_LinkClicked({ if (Test-Path $LOG) { Start-Process notepad.exe $LOG } })

# ---- o segredo do Miojo: digitar "miojo" na janela, ou clicar 5 vezes na assinatura
$script:digitado = ''
$script:cliques = 0
function Segredo() {
    $titulo.Text = "Ocarina Recomp $TIGELA"
    $sub.Text = (L 'Edição especial do Miojo: 3 minutos de fogo e várias horas de recompilação.' 'Miojo special edition: 3 minutes on the stove and many hours of recompiling.')
    [Windows.Forms.MessageBox]::Show((L "Você achou o miojo escondido!`n`nMiojo manda um salve para quem lê até o rodapé.`nTem outro escondido dentro do jogo: tente digitar o mesmo nome lá." "You found the hidden noodles!`n`nMiojo says hi to everyone who reads the footer.`nThere is another one inside the game: try typing the same name there."), (L "$TIGELA Segredo do Miojo" "$TIGELA Miojo's secret")) | Out-Null
}
$form.add_KeyPress({
    param($s, $e)
    $script:digitado = ($script:digitado + [string]$e.KeyChar).ToLower()
    if ($script:digitado.Length -gt 5) { $script:digitado = $script:digitado.Substring($script:digitado.Length - 5) }
    if ($script:digitado -eq 'miojo') { $script:digitado = ''; Segredo }
})
$rodape.add_Click({ $script:cliques++; if ($script:cliques -eq 5) { $script:cliques = 0; Segredo } })

# ---- mostrar o andamento e rodar programas sem janela preta
# The log may be held for a moment by a program that just wrote to it: losing one line must not stop the install.
function Registrar($t) {
    foreach ($tentativa in 1..20) {
        try { [IO.File]::AppendAllText($LOG, "[$(Get-Date -Format 'HH:mm:ss')] $t`r`n"); return } catch { Start-Sleep -Milliseconds 100 }
    }
}

function UltimaLinha() {
    try {
        $fs = [IO.File]::Open($LOG, 'Open', 'Read', 'ReadWrite,Delete')
        $n = [Math]::Min(4096, $fs.Length)
        $fs.Seek(-$n, 'End') | Out-Null
        $b = New-Object byte[] $n
        $fs.Read($b, 0, $n) | Out-Null
        $fs.Close()
        $linhas = [Text.Encoding]::UTF8.GetString($b) -split "[`r`n]+" | Where-Object { $_.Trim() }
        if ($linhas) { return ($linhas | Select-Object -Last 1) }
    } catch {}
    return ''
}

function Atualizar() {
    $l = UltimaLinha
    $texto = $l -replace '[^\x20-\x7E]', ''
    $lbLinha.Text = if ($texto.Length -gt 180) { $texto.Substring(0, 180) } else { $texto }
    # andamento de verdade quando o programa informa ("[12/660]" ou "20000/186587 files"), senao pelo tempo estimado
    $frac = [Math]::Min(0.95, ([DateTime]::Now - $script:passoIni).TotalMinutes / $script:estimativa)
    if ($l -match '\[(\d+)/(\d+)\]|(\d+)/(\d+) files') {
        $a = if ($Matches[1]) { [double]$Matches[1] } else { [double]$Matches[3] }
        $b = if ($Matches[2]) { [double]$Matches[2] } else { [double]$Matches[4] }
        if ($b -gt 0 -and $a -le $b) { $frac = $a / $b }
    }
    $total = $script:feito + $script:pesoAtual * $frac
    $barra.Value = [Math]::Min(1000, [int](1000 * $total))
    $lbPct.Text = (L '{0:0}% concluído' '{0:0}% done') -f (100 * $total)
    $dica = [int]([long]([DateTime]::Now.Ticks / 250000000) % $DICAS.Count)
    $lbDica.Text = $DICAS[$dica]
    [Windows.Forms.Application]::DoEvents()
}

function Exec([string]$exe, [string[]]$argumentos, [switch]$PodeFalhar, [string]$Saida) {
    # the full path: cmd.exe does not have to search PATH for it
    if ($exe -notmatch '\\') {
        $achado = Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($achado) { $exe = $achado.Source }
    }
    $q = ($argumentos | ForEach-Object { if ($_ -match '[\s&()^]') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $destino = if ($Saida) { "> `"$Saida`"" } else { ">> `"$LOG`"" }
    Registrar "> $exe $q"
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:ComSpec"
    $psi.Arguments = "/d /s /c `"`"$exe`" $q $destino 2>&1`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    if (Test-Path $script:pasta) { $psi.WorkingDirectory = $script:pasta }
    $script:proc = [Diagnostics.Process]::Start($psi)
    while (-not $script:proc.HasExited) {
        Atualizar
        if ($script:cancelar) {
            & taskkill.exe /T /F /PID $script:proc.Id 2>&1 | Out-Null
            throw 'CANCELADO'
        }
        Start-Sleep -Milliseconds 150
    }
    $cod = $script:proc.ExitCode
    if ($cod -ne 0 -and -not $PodeFalhar) { throw (L "O programa '$([IO.Path]::GetFileName($exe))' falhou (código $cod)." "The program '$([IO.Path]::GetFileName($exe))' failed (code $cod).") }
    return $cod
}

# cmd.exe stops finding programs when PATH is around 8 KB long, while PowerShell still finds them. This keeps each folder once,
# drops the ones that do not exist, and stops at 7000 characters with what the install needs first.
function LimparPath([string]$lista) {
    $vistos = @{}; $saida = New-Object Collections.ArrayList; $tamanho = 0
    foreach ($item in $lista -split ';') {
        $d = $item.Trim().Trim('"')
        if (-not $d -or $vistos.ContainsKey($d.ToLower()) -or -not [IO.Directory]::Exists($d)) { continue }
        if ($tamanho + $d.Length + 1 -gt 7000) { break }
        $vistos[$d.ToLower()] = $true; [void]$saida.Add($d); $tamanho += $d.Length + 1
    }
    return ($saida -join ';')
}
function AtualizarPath() {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine'); $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:PATH = LimparPath "$MSYS\ucrt64\bin;$VS;$env:LOCALAPPDATA\Microsoft\WindowsApps;$m;$u;$env:PATH"
}
function Tem($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Winget($id, $override) {
    $a = @('install', '--id', $id, '-e', '--silent', '--accept-source-agreements', '--accept-package-agreements')
    if ($override) { $a += @('--override', $override) }
    Exec 'winget' $a -PodeFalhar | Out-Null
    AtualizarPath
}
function TemCpp() {
    if (-not (Test-Path "$VS\vswhere.exe")) { return $false }
    $vc = & "$VS\vswhere.exe" -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    return ([bool]$vc -and (Test-Path "${env:ProgramFiles(x86)}\Windows Kits\10\Lib\*\um\x64\kernel32.lib"))
}

# ---- os passos: nome, minutos estimados e o que fazem
function P-Ferramentas() {
    AtualizarPath
    if (-not (Tem 'winget')) { throw 'WINGET' }
    if (-not (Tem 'git')) { Winget 'Git.Git' }
    if ((Exec 'py' @('-3.12', '--version') -PodeFalhar) -ne 0) { Winget 'Python.Python.3.12' }
    if (-not (Test-Path "$MSYS\usr\bin\bash.exe")) { Winget 'MSYS2.MSYS2' }
    if (-not (TemCpp)) {
        $existente = if (Test-Path "$VS\vswhere.exe") { & "$VS\vswhere.exe" -latest -prerelease -products '*' -property installationPath } else { $null }
        if ($existente) {
            $a = "modify --installPath `"$existente`" --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --quiet --norestart --force"
            $p = Start-Process "$VS\setup.exe" -ArgumentList $a -Verb RunAs -PassThru
            while (-not $p.HasExited) { Atualizar; Start-Sleep -Milliseconds 200 }
        } else {
            Winget 'Microsoft.VisualStudio.BuildTools' '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
        }
        if (-not (TemCpp)) { throw 'CPP' }
    }
    $sdks = (Tem 'dotnet') -and (& dotnet --list-sdks | Select-String '^10\.')
    if (-not $sdks) { Winget 'Microsoft.DotNet.SDK.10' }
    foreach ($c in 'git', 'py', 'dotnet') { if (-not (Tem $c)) { throw (L "A ferramenta '$c' não foi instalada." "The tool '$c' was not installed.") } }
    if (-not (Test-Path "$MSYS\usr\bin\bash.exe")) { throw (L 'O MSYS2 não foi instalado.' 'MSYS2 was not installed.') }
}
function P-Compilador() {
    $env:MSYSTEM = 'UCRT64'; $env:CHERE_INVOKING = '1'
    $bash = "$MSYS\usr\bin\bash.exe"
    if (-not (Test-Path "$MSYS\ucrt64\bin\clang.exe")) {
        # a primeira atualizacao pode fechar o proprio MSYS2: por isso duas vezes e sem parar no codigo de saida
        Exec $bash @('-lc', 'pacman -Syuu --noconfirm') -PodeFalhar | Out-Null
        Exec $bash @('-lc', 'pacman -Syuu --noconfirm') -PodeFalhar | Out-Null
    }
    Exec $bash @('-lc', 'pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-{clang,lld,ninja,gcc,make,pkgconf,sdl3,opus,libvpx,dav1d,zstd,vulkan-devel,vulkan-memory-allocator,vulkan-validation-layers,shaderc,spirv-tools} base-devel git unzip') | Out-Null
    AtualizarPath
    $env:PYTHONUTF8 = '1'
}
function P-Codigo() {
    if (Test-Path (Join-Path $script:pasta '.git')) {
        Exec 'git' @('-C', $script:pasta, 'pull', '--ff-only') | Out-Null
    } else {
        Exec 'git' @('clone', '-b', $RAMO, $REPO, $script:pasta) | Out-Null
    }
    $venv = Join-Path $script:pasta '.venv\Scripts\python.exe'
    if (-not (Test-Path $venv)) { Exec 'py' @('-3.12', '-m', 'venv', (Join-Path $script:pasta '.venv')) | Out-Null }
    Exec $venv @('-m', 'pip', 'install', '-q', '--disable-pip-version-check', '-r', (Join-Path $script:pasta 'tools\requirements-build.txt')) | Out-Null
    $script:py = $venv
}
function Build($sub) { return Join-Path $script:pasta "build\$sub" }

function OpcoesNup() {
    $saida = Build 'lista-nup.txt'
    New-Item -ItemType Directory -Force (Join-Path $script:pasta 'build') | Out-Null
    Exec $script:py @('tools\extract_nup.py', $script:jogo, '--list') -Saida $saida | Out-Null
    $script:nupOpcoes = if ((Get-Content $saida -Raw) -match ': 1 package') { @('--package', '0') } else { @('--overlay-update') }
}

function P-Exefs() {
    $exefs = Build 'exefs'
    if ((Test-Path "$exefs\main") -and (Get-FileHash "$exefs\main").Hash -eq $HASH_MAIN) { return }
    $origem = $null
    if ($script:jogoNup) {
        OpcoesNup
        Exec $script:py (@('tools\extract_nup.py', $script:jogo, '--out', (Build 'dump'), '--only', 'exefs', '--quiet') + $script:nupOpcoes) | Out-Null
        $origem = Build 'dump\exefs'
    } else {
        $origem = Join-Path $script:jogo 'exefs'
    }
    New-Item -ItemType Directory -Force $exefs | Out-Null
    Get-ChildItem -LiteralPath $origem -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $exefs $_.Name) -Force }
    if ((Get-FileHash "$exefs\main").Hash -ne $HASH_MAIN) {
        # o main costuma vir comprimido com ZBIC: descomprime com o codigo aberto do zbic
        $zb = Build 'zbic'
        if (-not (Test-Path "$zb\.git")) { Exec 'git' @('clone', 'https://github.com/kinnay/zbic', $zb) | Out-Null }
        Exec 'git' @('-C', $zb, 'checkout', '-q', $ZBIC) | Out-Null
        Exec "$MSYS\ucrt64\bin\clang.exe" @('-O2', '-w', "-I$zb\src", 'tools\oot\unzbic.c', '-o', (Build 'unzbic.exe')) | Out-Null
        Exec (Build 'unzbic.exe') @("$origem\main", "$exefs\main") -PodeFalhar | Out-Null
        if ((Get-FileHash "$exefs\main").Hash -ne $HASH_MAIN) { throw 'VERSAO' }
    }
    if ($script:jogoNup) { Remove-Item (Build 'dump') -Recurse -Force }
}
function P-Tradutor() { Exec $script:py @('tools\build_xlate.py') | Out-Null }
function P-Gerar() {
    Exec $script:py @('recomp\gen.py', '--exefs', (Build 'exefs'), '--out', 'generated\oot111', '--modules', 'main,sdk,subsdk0') | Out-Null
    Exec $script:py @('tools\oot\patch_generated.py', 'generated\oot111') | Out-Null
}
function P-Romfs() {
    if (Test-Path (Build 'romfs\index.json')) { return }
    if ($script:jogoNup) {
        OpcoesNup
        Exec $script:py (@('tools\extract_nup.py', $script:jogo, '--out', (Build 'dump'), '--only', 'romfs') + $script:nupOpcoes) | Out-Null
        # --consume apaga cada arquivo solto ao coloca-lo na imagem: so na copia extraida aqui, nunca na pasta da pessoa
        Exec $script:py @('tools\pack_romfs.py', '--dir', (Build 'dump\romfs'), '--out', (Build 'romfs'), '--consume') | Out-Null
        Remove-Item (Build 'dump') -Recurse -Force
    } else {
        Exec $script:py @('tools\pack_romfs.py', '--dir', (Join-Path $script:jogo 'romfs'), '--out', (Build 'romfs')) | Out-Null
    }
}
function P-Exe() {
    $ramGb = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $jobs = [Math]::Max(2, [Math]::Min([Environment]::ProcessorCount, [int]($ramGb / 3)))
    Exec $script:py @('tools\build_game.py', '--version', 'oot111', '--gen', 'generated\oot111', '--out', (Build 'oot111'), '--expected', 'tools\data\expected-oot111.json', '--exefs', (Build 'exefs'), '--romfs', (Build 'romfs'), '--jobs', "$jobs") | Out-Null
}
function P-Finalizar() {
    $ini = Build 'oot111\totk.ini'
    if (-not (Test-Path $ini)) { Copy-Item (Join-Path $script:pasta 'jogar\totk.ini') $ini }
    if ($env:OCARINA_AUTO) { return }
    $ws = New-Object -ComObject WScript.Shell
    $atalho = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Ocarina Recomp.lnk'))
    $atalho.TargetPath = 'powershell.exe'
    $atalho.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script:pasta\jogar\jogar-ocarina.ps1`""
    $atalho.WorkingDirectory = $script:pasta
    $atalho.IconLocation = (Build 'oot111\ocarina.exe')
    $atalho.Save()
}

$PASSOS = @(
    @((L 'Instalar ferramentas' 'Install tools'), 20, 'P-Ferramentas'),
    @((L 'Preparar o compilador' 'Prepare the compiler'), 8, 'P-Compilador'),
    @((L 'Baixar o Ocarina Recomp' 'Download Ocarina Recomp'), 3, 'P-Codigo'),
    @((L 'Conferir o seu jogo' 'Check your game'), 2, 'P-Exefs'),
    @((L 'Compilar o tradutor de shaders' 'Build the shader translator'), 5, 'P-Tradutor'),
    @((L 'Converter o código do jogo' 'Convert the game code'), 2, 'P-Gerar'),
    @((L 'Preparar os arquivos do jogo' 'Prepare the game files'), 25, 'P-Romfs'),
    @((L 'Compilar o jogo (a parte mais demorada)' 'Build the game (the longest part)'), 35, 'P-Exe'),
    @((L 'Criar o atalho' 'Create the shortcut'), 1, 'P-Finalizar')
)

function Explicar($erro) {
    $trecho = ''
    try { $trecho = (Get-Content $LOG -Tail 40 -ErrorAction SilentlyContinue) -join "`n" } catch {}
    if ($erro -eq 'WINGET') { return (L "O Windows não tem o 'Instalador de Aplicativo'.`n`nAbra a Microsoft Store, procure por 'Instalador de Aplicativo', atualize e abra este instalador de novo." "Windows does not have the 'App Installer'.`n`nOpen the Microsoft Store, search for 'App Installer', update it and open this installer again.") }
    if ($erro -eq 'CPP') { return (L "Faltam as ferramentas de C++ da Microsoft.`n`nAbra o 'Visual Studio Installer', clique em Modificar, marque 'Desenvolvimento para desktop com C++', instale e abra este instalador de novo." "Microsoft's C++ tools are missing.`n`nOpen the 'Visual Studio Installer', click Modify, select 'Desktop development with C++', install it and open this installer again.") }
    if ($erro -eq 'VERSAO') { return (L "Este jogo não é a versão 1.1.1, a única que funciona por enquanto.`n`nConfira o arquivo escolhido e tente de novo." "This game is not version 1.1.1, the only one that works for now.`n`nCheck the file you chose and try again.") }
    if ($trecho -match 'No space left|not enough space|espa.o insuficiente|Disk full') { return (L "O disco ficou cheio.`n`nLibere espaço e abra este instalador de novo: ele continua de onde parou." "The disk is full.`n`nFree some space and open this installer again: it picks up where it stopped.") }
    if ($trecho -match 'Could not resolve|Failed to connect|timed out|unable to access|Connection') { return (L "Parece ser um problema de internet.`n`nConfira a conexão e abra este instalador de novo: ele continua de onde parou." "This looks like an internet problem.`n`nCheck your connection and open this installer again: it picks up where it stopped.") }
    return (L "$erro`n`nAbra o instalador de novo: muitas vezes ele resolve sozinho. Se faltou uma ferramenta, instale à mão pelo passo 1 do guia: github.com/sostenesfreitas/ocarina-recomp/blob/main/docs/compilar-manual.md`n`nSe repetir, abra um pedido de ajuda no GitHub do projeto com o registro da instalação." "$erro`n`nOpen the installer again: this often fixes it. If a tool is missing, install it by hand with step 1 of the guide: github.com/sostenesfreitas/ocarina-recomp/blob/main/docs/build-by-hand.md`n`nIf it happens again, open an issue on the project's GitHub with the install log.")
}

function Instalar() {
    $tela1.Visible = $false; $tela2.Visible = $true
    $script:rodando = $true
    $total = ($PASSOS | ForEach-Object { $_[1] } | Measure-Object -Sum).Sum
    foreach ($p in $PASSOS) { [void]$lista.Items.Add("      $($p[0])") }
    Set-Content -Path $LOG -Value "Ocarina Recomp, instalador, $(Get-Date)" -Encoding UTF8
    try {
        for ($i = 0; $i -lt $PASSOS.Count; $i++) {
            $p = $PASSOS[$i]
            $lista.Items[$i] = " >  $($p[0])..."
            $script:passoIni = [DateTime]::Now; $script:estimativa = $p[1]; $script:pesoAtual = $p[1] / $total
            Registrar "=== $($p[0])"
            if ($i -ge 3 -or (Test-Path $script:pasta)) { if (Test-Path $script:pasta) { Set-Location $script:pasta } }
            & $p[2]
            $script:feito += $script:pesoAtual
            $lista.Items[$i] = " OK  $($p[0])"
        }
        $barra.Value = 1000
        $lbPct.Text = (L 'Pronto! 100%' 'Done! 100%')
        $lbLinha.Text = ''
        $lbDica.Text = (L "Conecte um controle e bom jogo!`nNa primeira vez, a vegetação pode levar alguns minutos para aparecer e áreas novas podem travar um pouco: é normal. Não compartilhe o jogo montado, os saves nem o cache: eles saem do seu jogo." "Plug in a controller and have fun!`nThe first time, plants can take a few minutes to appear and new areas may stutter a little: that is normal. Do not share the built game, the saves or the cache: they come from your game.")
        $btJogar.Visible = $true; $btFechar.Visible = $true
        $script:rodando = $false
        if ($env:OCARINA_AUTO) { Registrar 'INSTALACAO CONCLUIDA'; $form.Close() }
    } catch {
        $script:rodando = $false
        $msg = "$($_.Exception.Message)"
        Registrar "ERRO: $msg"
        if ($msg -eq 'CANCELADO') { $form.Close(); return }
        $lbPct.Text = (L 'A instalação parou.' 'The installation stopped.')
        $btFechar.Visible = $true
        if ($env:OCARINA_AUTO) { $form.Close(); return }
        $r = [Windows.Forms.MessageBox]::Show((Explicar $msg) + (L "`n`nQuer ver o registro da instalação?" "`n`nDo you want to see the install log?"), 'Ocarina Recomp', 'YesNo', 'Warning')
        if ($r -eq 'Yes') { Start-Process notepad.exe $LOG }
    }
}

# ---- tela 1: logica
function PastaPadrao() {
    $livre = { param($d) [Math]::Floor((Get-PSDrive $d).Free / 1GB) }
    if ((& $livre 'C') -ge $GB_NECESSARIOS) { return 'C:\OcarinaRecomp' }
    $melhor = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -and $_.Name.Length -eq 1 } | Sort-Object Free -Descending | Select-Object -First 1
    return "$($melhor.Name):\OcarinaRecomp"
}
function Validar() {
    $problema = @()
    $unid = $script:pasta.Substring(0, 1)
    $livre = [Math]::Floor((Get-PSDrive $unid).Free / 1GB)
    $parcial = Test-Path (Join-Path $script:pasta 'build\romfs\index.json')
    if ($script:pasta -match '[^\x21-\x7E]|[\[\]%&]') { $problema += (L 'A pasta de instalação não pode ter espaços nem acentos.' 'The install folder cannot have spaces or accents.') }
    elseif (-not $parcial -and $livre -lt $GB_NECESSARIOS) { $problema += (L "Faltam $($GB_NECESSARIOS - $livre) GB livres em ${unid}: (precisa de $GB_NECESSARIOS GB)." "You need $($GB_NECESSARIOS - $livre) GB more free on ${unid}: ($GB_NECESSARIOS GB required).") }
    $lbPasta.Text = (L "$($script:pasta)   ($livre GB livres)" "$($script:pasta)   ($livre GB free)")
    $lbAviso.Text = ($problema + $script:avisos) -join "`n"
    $btInstalar.Enabled = ($problema.Count -eq 0) -and [bool]$script:jogo -and -not $script:bloqueio
}
function EscolherJogo([string]$c) {
    # -LiteralPath: game files are often named with [title id], and [ ] are wildcards to the plain -Path
    if ($c -match '\.nup$' -and (Test-Path -LiteralPath $c -PathType Leaf)) {
        $script:jogo = $c; $script:jogoNup = $true
        $lbJogo.Text = (L "Jogo: $c" "Game: $c"); $lbJogo.ForeColor = [Drawing.Color]::DarkGreen
    } else {
        $b = if (Test-Path -LiteralPath (Join-Path $c 'base\exefs\main')) { Join-Path $c 'base' } else { $c }
        if ((Test-Path -LiteralPath (Join-Path $b 'exefs\main')) -and (Test-Path -LiteralPath (Join-Path $b 'romfs'))) {
            $script:jogo = $b; $script:jogoNup = $false
            $lbJogo.Text = (L "Jogo: $b" "Game: $b"); $lbJogo.ForeColor = [Drawing.Color]::DarkGreen
        } else {
            $script:jogo = $null
            $lbJogo.Text = (L 'Essa pasta não tem as subpastas exefs e romfs do jogo. Escolha a pasta certa.' 'This folder does not have the game''s exefs and romfs subfolders. Choose the right folder.'); $lbJogo.ForeColor = [Drawing.Color]::Firebrick
        }
    }
    Validar
}
$btArq.add_Click({
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Title = (L 'Escolha o arquivo do seu jogo' 'Choose your game file'); $d.Filter = (L 'Jogo (*.nup)|*.nup' 'Game (*.nup)|*.nup')
    if ($d.ShowDialog($form) -eq 'OK') { EscolherJogo $d.FileName }
})
$btPasta.add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    $d.Description = (L 'Escolha a pasta do jogo, a que tem exefs e romfs dentro' 'Choose the game folder, the one with exefs and romfs inside')
    if ($d.ShowDialog($form) -eq 'OK') { EscolherJogo $d.SelectedPath }
})
$btTrocar.add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    $d.Description = (L 'Escolha onde instalar (sem espaços nem acentos no caminho)' 'Choose where to install (no spaces or accents in the path)')
    if ($d.ShowDialog($form) -eq 'OK') { $script:pasta = Join-Path $d.SelectedPath 'OcarinaRecomp'; Validar }
})
$btInstalar.add_Click({ Instalar })
$btJogar.add_Click({
    Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script:pasta\jogar\jogar-ocarina.ps1`""
    $form.Close()
})
$btFechar.add_Click({ $form.Close() })
$form.add_FormClosing({
    param($s, $e)
    if (-not $script:rodando) { return }
    $e.Cancel = $true
    $r = [Windows.Forms.MessageBox]::Show((L "Parar a instalação agora?`n`nDepois é só abrir o instalador de novo: ele continua de onde parou." "Stop the installation now?`n`nYou can just open the installer again later: it picks up where it stopped."), 'Ocarina Recomp', 'YesNo', 'Question')
    if ($r -eq 'Yes') { $script:cancelar = $true }
})

# ---- verificacoes do PC, antes de qualquer coisa
$script:avisos = @()
$script:bloqueio = $false
$script:jogo = $null; $script:jogoNup = $false; $script:nupOpcoes = @('--overlay-update')
$script:pasta = if ($env:OCARINA_PASTA) { $env:OCARINA_PASTA } else { PastaPadrao }
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { $script:avisos += (L 'Este instalador só funciona em Windows de 64 bits.' 'This installer only works on 64-bit Windows.'); $script:bloqueio = $true }
$ram = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
if ($ram -lt 15) { $script:avisos += (L "Este PC tem $ram GB de RAM. Com menos de 16 GB, nunca testamos: a compilação ou o jogo podem falhar." "This PC has $ram GB of RAM. We never tested with less than 16 GB: the build or the game may fail.") }
$gpus = (Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ', '
if ($gpus -notmatch 'NVIDIA') { $script:avisos += (L "Só testamos em placa NVIDIA. Sua placa ($gpus) pode não funcionar." "We only tested on NVIDIA cards. Your card ($gpus) may not work.") }
Validar
if ($env:OCARINA_JOGO) { EscolherJogo $env:OCARINA_JOGO }
if ($env:OCARINA_AUTO) { if (-not $script:jogo) { throw 'OCARINA_JOGO: jogo nao encontrado' }; $form.add_Shown({ Instalar }) }

try { [void][Windows.Forms.Application]::Run($form) }
catch {
    Registrar "ERRO GERAL: $($_.Exception.Message)"
    [Windows.Forms.MessageBox]::Show((L "O instalador encontrou um erro:`n`n$($_.Exception.Message)`n`nRegistro: $LOG" "The installer hit an error:`n`n$($_.Exception.Message)`n`nLog: $LOG"), 'Ocarina Recomp', 'OK', 'Error') | Out-Null
}
