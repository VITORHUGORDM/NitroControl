# NitroControl

Painel de controle no estilo do NitroSense para notebooks **Acer Nitro**, que funciona no **Windows 10 e 11**.
Foi feito para o **Nitro V 15 (ANV15-52, RTX 4060)**, cujo NitroSense oficial só funciona no Windows 11.

> Projeto independente, sem ligação com a Acer. NitroSense é marca da Acer.

## Download

Baixe o **`NitroControl-Setup.exe`** na página [Releases](../../releases/latest) e abra o arquivo.
Ele cria atalhos na Área de Trabalho e no Menu Iniciar. Para desinstalar, use **Configurações → Aplicativos instalados → NitroControl**.

O instalador não tem assinatura digital. Se o Windows SmartScreen avisar "editor desconhecido", clique em **Mais informações → Executar assim mesmo**.

## O que ele faz

| Aba | Funções |
|---|---|
| **Início** | Frequência e uso da GPU e da CPU; temperaturas da GPU, da CPU e do sistema |
| **Modo** | Silencioso, Equilibrado e Desempenho; troca automática ao ligar ou desligar o carregador |
| **Ventoinhas** | Automático, Máximo ou Personalizado, com velocidade de CPU e GPU de 20% a 100% |
| **Configurações** | Limite de carga da bateria em 80%; iniciar com o Windows |

Com **Iniciar com o Windows** ligado, as últimas escolhas são reaplicadas ao entrar no Windows e ao sair da suspensão.
Com **Troca automática** ligada, ao tirar o carregador o app muda para o modo da bateria e põe as ventoinhas no automático. Ao conectar, volta para o modo da tomada.

## Como funciona

Não usa driver nem programa extra. O app conversa com a interface WMI da própria BIOS (`AcerGamingFunction` e `BatteryControl`), a mesma usada pelo NitroSense.
Os códigos dos comandos foram tirados dos drivers `acer-wmi` e `acer-wmi-battery` do Linux.

- `NitroControl.ps1`: um servidor local em `localhost`, com token de acesso aleatório, que roda como administrador e fala com a BIOS.
- `ui.html`: a interface, aberta numa janela do Edge ou do Chrome sem barra de endereço.
- `run.vbs`: abre o app sem mostrar a janela do PowerShell.
- As configurações ficam em `%LOCALAPPDATA%\NitroControl\settings.json`.
- As tarefas agendadas `NitroControl` (login e saída da suspensão) e `NitroControl Energia` (carregador ligado ou desligado) rodam `run.vbs -Apply`.

## Lançar uma versão nova

1. Edite os arquivos e teste com `NitroControl.bat`, que roda direto desta pasta.
2. Atualize `DisplayVersion` em `install.ps1`.
3. Rode `powershell -ExecutionPolicy Bypass -File build.ps1`, que gera o `NitroControl-Setup.exe` com o IExpress do Windows.
4. Faça o commit e publique a versão:
   ```
   gh release create v1.1 NitroControl-Setup.exe --title "v1.1" --notes "O que mudou"
   ```

`make-icon.ps1` gera o `icon.ico` de novo, caso você queira mudar o ícone.

## Compatibilidade e avisos

- Testado no **ANV15-52**. Outros Acer Nitro e Predator com a mesma interface WMI provavelmente funcionam, mas não foram testados.
- Não use junto com o NitroSense, porque um desfaz as configurações do outro.
- O app consulta a GPU pelo `nvidia-smi`, o que pode manter a placa ligada enquanto a janela estiver aberta.
- Use por sua conta e risco.
