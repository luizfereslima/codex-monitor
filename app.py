from flask import Flask, jsonify, render_template_string
from usage import ler_logs

app = Flask(__name__)

HTML_PAINEL = """
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Codex Pulse</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #1e1e2e; color: #cdd6f4; margin: 0; padding: 16px;
      display: flex; flex-direction: column; justify-content: center; min-height: 100vh; box-sizing: border-box;
    }
    h3 { margin: 0 0 12px 0; font-size: 15px; color: #89b4fa; display: flex; justify-content: space-between; }
    .grupo { margin-bottom: 14px; }
    .label-row { display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 4px; }
    .bar-bg { background: #313244; height: 10px; border-radius: 5px; overflow: hidden; }
    .bar-fill { height: 100%; width: 0%; transition: width 0.4s ease, background 0.4s ease; }
    .footer { font-size: 10px; color: #6c7086; text-align: right; margin-top: 4px; }
    .renovacao { font-size: 10px; color: #a6adc8; margin-top: 5px; }
    .erro { color: #f38ba8; }
  </style>
</head>
<body>
  <h3><span>Codex Pulse</span><span id="status-dot" aria-label="Carregando">●</span></h3>
  
  <div class="grupo">
    <div class="label-row">
      <span>Últimas 5 horas</span>
      <span id="txt-sessao">Carregando...</span>
    </div>
    <div class="bar-bg"><div id="bar-sessao" class="bar-fill" style="background: #a6e3a1;"></div></div>
    <div id="renova-sessao" class="renovacao"></div>
  </div>

  <div class="grupo">
    <div class="label-row">
      <span>Últimos 7 dias</span>
      <span id="txt-semana">Carregando...</span>
    </div>
    <div class="bar-bg"><div id="bar-semana" class="bar-fill" style="background: #89b4fa;"></div></div>
    <div id="renova-semana" class="renovacao"></div>
  </div>

  <div class="footer" id="atualizado">Atualizando...</div>

  <script>
    const numeros = new Intl.NumberFormat('pt-BR');
    function corDoLimite(percentual) {
      if (percentual === null) return '#a6adc8';
      if (percentual <= 5) return '#ff2e8a';
      if (percentual <= 10) return '#ff573d';
      if (percentual <= 25) return '#ff9e0a';
      if (percentual <= 50) return '#f5d447';
      return '#00e675';
    }
    function mostrarJanela(nome, tokens, percentual, renovacao, estimado = false) {
      const texto = tokens === null ? 'Tokens indisponíveis' : `${numeros.format(tokens)} tokens`;
      const limite = percentual === null ? 'limite indisponível' : `${numeros.format(percentual)}%${estimado ? '*' : ''} restante`;
      const campo = document.getElementById(`txt-${nome}`);
      campo.textContent = `${texto} · ${limite}`;
      campo.style.color = corDoLimite(percentual);
      const barra = document.getElementById(`bar-${nome}`);
      barra.style.width = `${percentual === null ? 0 : Math.max(0, Math.min(percentual, 100))}%`;
      barra.style.background = corDoLimite(percentual);
      const data = renovacao ? new Date(renovacao) : null;
      document.getElementById(`renova-${nome}`).textContent = estimado
        ? 'Renovação estimada; aguardando dado do Codex'
        : data && !Number.isNaN(data.getTime())
          ? `Limite renova em ${data.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}`
          : 'Renovação indisponível';
    }

    async function atualizar() {
      try {
        const res = await fetch('/api/uso', { cache: 'no-store' });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const dados = await res.json();
        mostrarJanela('sessao', dados.sessao, dados.pct_restante_sessao, dados.renova_sessao, dados.limite_estimado_sessao);
        mostrarJanela('semana', dados.semana, dados.pct_restante_semana, dados.renova_semana, dados.limite_estimado_semana);
        const dot = document.getElementById('status-dot');
        dot.style.color = dados.status === 'ok'
          ? corDoLimite(Math.min(dados.pct_restante_sessao, dados.pct_restante_semana))
          : '#ff573d';
        dot.setAttribute('aria-label', dados.status);
        const rodape = document.getElementById('atualizado');
        rodape.classList.toggle('erro', dados.status !== 'ok');
        rodape.textContent = `${dados.status === 'ok' ? 'Atualizado' : dados.mensagem} · leitura às ${dados.hora}`;
      } catch (e) {
        mostrarJanela('sessao', null, null, null);
        mostrarJanela('semana', null, null, null);
        const dot = document.getElementById('status-dot');
        dot.style.color = '#f38ba8';
        dot.setAttribute('aria-label', 'erro');
        const rodape = document.getElementById('atualizado');
        rodape.classList.add('erro');
        rodape.textContent = 'Erro ao consultar /api/uso';
      }
    }
    atualizar();
    setInterval(atualizar, 5000);
  </script>
</body>
</html>
"""


@app.route("/")
def index():
    return render_template_string(HTML_PAINEL)

@app.route("/api/uso")
def api_uso():
    return jsonify(ler_logs())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5055)
