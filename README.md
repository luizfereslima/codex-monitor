# Codex Pulse

Mostra o percentual restante dos limites do Codex. A janela do macOS também mostra o consumo de tokens quando expandida. A página web continua disponível. Os dados são atualizados a cada 5 segundos.

Se o horário de renovação passar antes de o Codex gravar novo evento, o painel mostra 100% com `*` como estimativa. Assim que chegar um novo registro, substitui a estimativa pelo percentual confirmado.

## Janela do macOS

No Mac em que você usa o Codex, clique no ícone **Iniciar Codex Pulse** na Mesa, clique duas vezes em `iniciar-monitor.command`, ou execute no Terminal:

```sh
cd /Users/luizfelipelima/CriaCode/codex-monitor
./iniciar-monitor.command
```

O comando abre `CodexPulse.app` sem Docker. A janela lê os arquivos locais de `~/.codex/sessions` e aparece no canto inferior direito da área útil da tela, ao lado do Dock. Pode ser redimensionada ou arrastada; posição, tamanho e layout escolhido são lembrados. A opção **Sempre à frente** mantém a janela acima das demais.

Ao diminuir a altura, o painel passa para uma versão média e depois para uma faixa de uma linha, junto ao Dock. Ela sempre mostra **5 h** e **7 dias**, cada um com percentual restante e barra, qualquer que seja o layout selecionado na janela expandida. Tokens e horários de renovação ficam nos layouts expandidos. A largura mínima é de 320 px e a altura mínima do conteúdo é de 36 px. Aumente a janela para trocar de layout. A janela fica rente à borda útil acima do Dock quando é aberta ou redimensionada nessa posição.

Se a faixa mostrar **Aguardando dados do Codex**, abra o Codex e faça uma interação. O painel lê os limites registrados em `~/.codex/sessions`; enquanto esses dados não existirem, a janela expandida mostra uma explicação no rodapé.

A cor do percentual restante muda em cinco faixas: verde acima de 50%, amarelo até 50%, laranja até 25%, vermelho até 10% e rosa até 5%.

Layouts disponíveis:

- **Resumo:** tokens, percentual restante e renovação dos limites de 5 horas e 7 dias.
- **Limites:** percentuais restantes e tempo até cada renovação.
- **Atividade:** tokens de entrada, saída e cache de entrada, eventos de uso, sessões com uso e horário da última atividade nas últimas 5 horas. O cache de entrada faz parte dos tokens de entrada.

Se o app precisar ser recompilado após alteração no código:

```sh
./build-macos-app.sh
```

## Página web

Se quiser usar a página web no futuro, inicie o servidor manualmente:

```sh
docker compose up --build -d
```

Depois, abra <http://localhost:5055>.

Para parar o servidor:

```sh
docker compose down
```

O servidor lê `~/.codex/sessions` em modo somente leitura dentro do Docker. A janela lê esses arquivos diretamente no macOS.
