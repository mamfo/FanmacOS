# FanmacOS

App de barra de menus para macOS que mostra as temperaturas do hardware junto ao relógio e permite controlar as ventoinhas. Desenvolvido por [mamfo.net](https://mamfo.net).

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-AppKit-orange)

## Funcionalidades

- Temperatura da CPU em tempo real na barra de menus, com ícone e cor por faixa (normal, morna, quente).
- Cápsulas de largura fixa e altura proporcional à barra (20–22 px), num único item, para a barra não se deslocar quando os valores mudam.
- O macOS é que decide a ordem dos itens da barra; para colocar o item junto ao relógio, arrasta-o com **⌘** e a posição fica guardada.
- Menu com CPU (máxima e média), SSD/NAND, outros sensores e a lista completa de sensores.
- Escolha do que mostrar na barra: CPU, máxima do sistema, SSD, sensor específico ou apenas o ícone.
- Intervalo de atualização configurável (1, 2, 5, 10 ou 30 segundos).
- Celsius ou Fahrenheit.
- Início automático ao iniciar sessão.
- Ventoinhas: RPM em tempo real, velocidade manual por ventoinha, botão de máximo e regresso ao automático.
- Rede: velocidade de receção (↓) e envio (↑), total e por interface, na barra e no menu, com cores distintas.
- Discos: velocidade de leitura (R) e escrita (W) de cartões SD, pen USB e discos externos, com cápsulas na barra quando há mídia externa.
- Atualizações automáticas via GitHub Releases.
- Temperaturas sem root nem permissões; o controlo das ventoinhas é autorizado uma única vez com a palavra-passe de administrador.

## Requisitos

- macOS 13 (Ventura) ou superior.
- Apple Silicon (M1/M2/M3/M4…). Os sensores são lidos via IOHID; em Macs Intel a lista pode ficar vazia.

## Compilar e executar

```bash
make build   # compila para build/FanmacOS.app
make run     # compila e abre
make dump    # imprime as leituras no terminal (teste rápido)
```

A compilação usa apenas as Command Line Tools (`swiftc`); não é preciso Xcode.

## Instalar neste Mac

```bash
make install   # copia para /Applications e abre
```

Depois, use o menu do app para ativar **Iniciar ao iniciar sessão**.

Para desinstalar:

```bash
make uninstall
```

## Instalar noutro Mac

```bash
make dist
```

Cria em `dist/`:

| Ficheiro | Uso |
| --- | --- |
| `FanmacOS-2.10.dmg` | abrir e arrastar `FanmacOS.app` para `Applications` |
| `FanmacOS-2.10.zip` | alternativa portátil, com a app já assinada |
| `FanmacOS-2.10.sha256` | somas de verificação |

O DMG inclui um ficheiro `LEIA-ME.txt` com os passos. No outro Mac:

1. Copia o DMG (AirDrop, rede, Pen USB…), abre-o e arrasta a app para **Applications**.
2. Abre a app. Se o macOS bloquear por ser de programador não identificado, clica com o botão direito na app e escolhe **Abrir** (ou vai a **Privacidade e Segurança → Abrir mesmo assim**).
3. Na primeira alteração das ventoinhas, autoriza o assistente com a palavra-passe de administrador.

Requisitos: Apple Silicon (M1 ou posterior) e macOS 13+. A app é assinada ad-hoc, não notarizada; por isso o aviso do Gatekeeper na primeira abertura.

> Também podes remover a marca de quarentena no Terminal:
> `xattr -dr com.apple.quarantine /Applications/FanmacOS.app`

## Atualizações automáticas

O código e os releases vivem em [github.com/mamfo/FanmacOS](https://github.com/mamfo/FanmacOS).

- A app verifica o último release ao arrancar e a cada 6 horas.
- Se estiver na pasta **Aplicações** e as atualizações automáticas estiverem ligadas (por omissão), descarrega o ZIP, confirma a soma SHA-256 publicada e a assinatura do código, substitui a app e reinicia-a.
- Em **menu → Procurar atualizações…** podes forçar a verificação; em **Atualizações automáticas** podes desligar o processo.
- Se a app estiver a correr a partir de outra pasta (por exemplo `build/`), a instalação automática é recusada e a app indica para a mover para **Aplicações**.

Para publicar uma versão nova:

1. Atualiza `CFBundleShortVersionString` em `Resources/Info.plist` (por exemplo `2.8`).
2. Faz commit e cria a tag `v2.8`; envia-a para o GitHub.
3. O workflow `.github/workflows/release.yml` compila a app num runner macOS, gera DMG, ZIP e SHA-256 e cria o release automaticamente.

A primeira instalação de uma versão com atualizador tem de ser feita manualmente (arrastar para Aplicações). A partir daí, as máquinas recebem as versões seguintes sem intervenção.

> As atualizações são autenticadas por HTTPS, pela soma SHA-256 do release e pela verificação da assinatura do bundle. A app não é notarizada, por isso a primeira abertura continua a precisar de **Abrir** no menu de contexto.

## Histórico

**Histórico…** no menu abre gráficos dos últimos 15 minutos de temperatura, rede e discos. O botão **Exportar CSV…** grava os dados em CSV para análise.

A amostragem é feita ao mesmo ritmo das leituras; o histórico fica só em memória e não sai do Mac.

## Energia

O menu **Energia** mostra a carga da CPU e GPU. Em Macs com bateria mostra também percentagem, temperatura, saúde, ciclos, estado de carga e potência do carregador. Em Macs sem bateria (ou ambientes virtualizados) a secção da bateria é omitida.

**Mostrar bateria na barra** acrescenta uma cápsula com ícone e percentagem, colorida por nível (verde ≥50%, laranja 20–49%, vermelho <20%) e verde enquanto carrega.

**Mostrar CPU na barra** e **Mostrar RAM na barra** acrescentam as percentagens de utilização, com os símbolos `cpu` e `memorychip`. A RAM é calculada a partir das páginas ativas, wired e comprimidas. Podes desligar qualquer métrica para manter a barra compacta.

Em Macs fixos (sem bateria), o consumo total do sistema é lido do SMC (`PSTR`, com fallback `PDTR`) e aparece no menu **Energia** e na barra como **W** com um raio. A opção **Mostrar consumo na barra** controla a cápsula.

**Poupar energia a baterias** (nas Definições) aumenta o intervalo para pelo menos 5 s quando estás a baterias.

## Definições e testes

Abre **Definições…** no menu (⌘,) para escolher os dados da barra, unidades, intervalo, alertas, ventoinhas e atualizações.

```bash
make test   # testes de lógica e geometria da interface
```

O CI corre os testes e a compilação; o workflow de release só publica se os testes passarem.

## Como funciona

O app usa a API `IOHIDEventSystemClient` (página de uso `0xFF00`, uso `5`) para ler os sensores de temperatura expostos pelo sistema. Sensores duplicados são agrupados pelo nome (fica o valor mais alto) e o sensor de calibração (`PMU tcal`) é ignorado.

Cada família é classificada assim:

| Grupo | Sensores |
| --- | --- |
| CPU | `PMU tdie*`, `PMU TP*` |
| Armazenamento | `NAND *` |
| Outros | restantes (`PMU tdev*`, etc.) |

### Rede

O tráfego é lido localmente através de `sysctl(NET_RT_IFLIST2)`, que expõe contadores de 64 bits por interface. São consideradas as interfaces físicas `en*` (Wi‑Fi, Ethernet, Thunderbolt, iPhone USB) e `pdp_ip*`; interfaces virtuais (`utun`, `awdl`, `llw`, `bridge`) não entram na soma. A velocidade é calculada entre amostras consecutivas e atualizada ao mesmo ritmo das temperaturas.

No menu aparecem os totais **↓ Receber** / **↑ Enviar** e um submenu **Interfaces** com cada placa. As cápsulas de rede fazem parte do item único da app, o mais à direita possível (junto ao relógio), e podem ser escondidas em **Mostrar rede na barra**.

### Discos

As estatísticas vêm do `IOBlockStorageDriver` do IOKit (`Bytes (Read)` / `Bytes (Write)`), sem root. Cada disco físico é identificado pelo nome BSD (`disk4`, etc.) e os metadados (nome, protocolo USB/SD, interno/virtual) são lidos com `diskutil info -plist` apenas quando um disco aparece.

- A barra mostra cápsulas **R** (leitura, azul-petróleo) e **W** (escrita, âmbar) com o total dos discos externos, dentro do item único da app.
- As cápsulas de disco aparecem automaticamente quando ligas um cartão SD, pen USB ou disco externo e desaparecem quando o retiras.
- Em **Mostrar discos na barra** podes desligar o item; **Incluir disco interno na barra** acrescenta o SSD interno.
- O menu **DISCOS** lista todos os discos físicos, incluindo o interno, com as velocidades de leitura/escrita.

Discos virtuais (imagens `.dmg`, contentores APFS sintetizados) são ignorados.

### Ventoinhas

A leitura de RPM usa as chaves `FNum`, `F{0}Ac`, `F{0}Mn`, `F{0}Mx`, `F{0}Tg` e `F{0}Md`/`F{0}md` do SMC — sem privilégios. O controlo manual escreve `F{0}Md = 1` e depois `F{0}Tg = rpm`; devolver ao automático escreve `F{0}Md = 0`. As velocidades são sempre limitadas ao mínimo e máximo reportados pelo hardware. Em modelos M3/M4+ o código tenta ainda o desbloqueio `Ftst` quando o firmware recusa o modo manual.

Escrever no SMC exige root. Na primeira alteração manual, o FanmacOS pede autorização de administrador e instala:

| Caminho | Função |
| --- | --- |
| `/Library/FanmacOS/fanctl` | assistente root que só sabe ler e alterar ventoinhas |
| `/etc/sudoers.d/fanmacos` | regra que permite ao utilizador executar apenas esse assistente |

O assistente pode ser removido em **menu → Remover assistente de ventoinhas…**, que também devolve as ventoinhas ao modo automático. Não há daemons, extensões de kernel nem processos residentes: o `fanctl` só corre quando é necessário.

No ecrã integrado do MacBook, a janela de controlo fica fixa ao lado esquerdo do notch/webcam (ancorada à área do notch).

Por omissão, o app devolve as ventoinhas ao modo automático ao sair. Se o app for forçado a encerrar (crash ou Force Quit), a velocidade manual pode permanecer ativa até usar **Tudo automático** ou reiniciar o Mac. Após acordar de suspensão — ou se o macOS alterar a velocidade — as velocidades manuais guardadas são reaplicadas.

### Curva automática e watchdog

Na janela das ventoinhas, **Curva automática pela temperatura da CPU** mapeia a temperatura (média de 3 leituras) entre **Início** e **Máximo** para a velocidade mínima/máxima das ventoinhas. A app escreve o alvo num ficheiro de controlo e inicia um processo root `fanctl watch`.

O processo de vigilância aplica o alvo a cada 2 s e verifica um heartbeat da app. Se a app fechar inesperadamente (ou ficar sem heartbeat durante 20 s), ou se o Mac acordar de suspensão sem a app retomar, as ventoinhas voltam automaticamente ao controlo do macOS. Ao desligar a curva ou sair normalmente, a app também repõe o automático.

> Aviso: o controlo manual/curva é fornecido tal como está. O firmware da Apple continua a ter proteções térmicas, mas usa velocidades baixas com cautela.

## Estrutura

```
Sources/
  main.swift              ponto de entrada e modo --dump
  AppDelegate.swift       barra de menus, menu e ações
  TemperatureMonitor.swift  leitura de temperaturas via IOHID
  Models.swift            amostras, grupos e agregações
  Preferences.swift       preferências persistidas
  Formatting.swift        formatação e cores
  MenuViews.swift         vistas personalizadas do menu
  SMC.swift               acesso de baixo nível ao AppleSMC
  FanControl.swift        leitura/escrita e limites das ventoinhas
  FanControlService.swift instalação e execução do assistente root
  FanWindow.swift         janela de controlo das ventoinhas
  NetworkMonitor.swift    contadores e velocidades de rede
  DiskMonitor.swift       estatísticas de leitura/escrita dos discos
  UpdateService.swift     verificação, download e instalação de versões
  fanctl/main.swift       binário que corre como root
  AppInfo.swift            versão e autor (rodapé e Sobre)
Resources/Info.plist       bundle do app (LSUIElement)
scripts/                 geração do ícone
build.sh / Makefile        build, instalação e distribuição
scripts/make-dist.sh       gera DMG e ZIP para outro Mac
.github/workflows/         CI que publica releases a partir de tags
```

## Notas

- Ícone, app e assistente são assinados ad-hoc (`codesign -s -`). Numa primeira abertura, o macOS pode pedir confirmação em **Privacidade e Segurança**.
- Se mover o app depois de ativar o início automático, desative e reative a opção.
- O assistente instalado pertence ao utilizador que autorizou a instalação. Se mudar de conta, remova-o e volte a instalar.
- Testado num MacBook Pro 16" (M1 Max) com macOS 26/27. Noutros modelos Apple Silicon as chaves de ventoinha podem variar.
