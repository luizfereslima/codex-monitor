"""Leitura local dos eventos de uso do Codex, sem dependências externas."""

import glob
import json
import os
from datetime import datetime, timedelta, timezone


PASTA_SESSIONS = os.environ.get("CODEX_SESSIONS_DIR", os.path.expanduser("~/.codex/sessions"))


def data_evento(valor):
    if not isinstance(valor, str):
        return None
    try:
        data = datetime.fromisoformat(valor.replace("Z", "+00:00"))
        return data if data.tzinfo else None
    except ValueError:
        return None


def limite_valido(valor):
    if not isinstance(valor, dict):
        return None
    percentual = valor.get("used_percent")
    renovacao = valor.get("resets_at")
    if isinstance(percentual, bool) or not isinstance(percentual, (int, float)):
        return None
    if isinstance(renovacao, bool) or not isinstance(renovacao, (int, float)):
        return None
    try:
        return float(percentual), datetime.fromtimestamp(renovacao, tz=timezone.utc)
    except (OverflowError, OSError, ValueError):
        return None


def estado_limite(limite, agora):
    if limite is None:
        return None, None, None, False
    _, usado, renovacao = limite
    if renovacao <= agora:
        # Não há novo snapshot até o Codex registrar outro evento.
        return 0.0, 100.0, None, True
    return usado, max(0, min(100, 100 - usado)), renovacao.isoformat(), False


def ler_logs(agora=None):
    agora = agora or datetime.now(timezone.utc)
    inicio_sessao = agora - timedelta(hours=5)
    inicio_semana = agora - timedelta(days=7)
    tokens_sessao = tokens_semana = 0
    entrada_sessao = saida_sessao = cache_sessao = 0
    eventos_sessao = eventos_semana = 0
    arquivos_ativos = set()
    ultima_atividade = None
    limites = {"primary": None, "secondary": None}
    erros = 0

    try:
        arquivos = glob.glob(os.path.join(PASTA_SESSIONS, "**", "*.jsonl"), recursive=True)
    except OSError:
        arquivos = []
        erros += 1
    if not os.path.isdir(PASTA_SESSIONS):
        erros += 1

    for arquivo in arquivos:
        try:
            if datetime.fromtimestamp(os.path.getmtime(arquivo), tz=timezone.utc) < inicio_semana:
                continue
            with open(arquivo, encoding="utf-8") as sessao:
                for linha in sessao:
                    try:
                        evento = json.loads(linha)
                    except (json.JSONDecodeError, UnicodeError):
                        # A última linha pode estar sendo gravada pelo Codex.
                        continue
                    if not isinstance(evento, dict) or evento.get("type") != "event_msg":
                        continue
                    payload = evento.get("payload")
                    if not isinstance(payload, dict) or payload.get("type") != "token_count":
                        continue
                    data = data_evento(evento.get("timestamp"))
                    if data is None or data < inicio_semana or data > agora:
                        continue

                    info = payload.get("info")
                    uso = info.get("last_token_usage") if isinstance(info, dict) else None
                    total = uso.get("total_tokens") if isinstance(uso, dict) else None
                    if isinstance(total, int) and not isinstance(total, bool) and total >= 0:
                        tokens_semana += total
                        eventos_semana += 1
                        if data >= inicio_sessao:
                            tokens_sessao += total
                            eventos_sessao += 1
                            arquivos_ativos.add(arquivo)
                            if ultima_atividade is None or data > ultima_atividade:
                                ultima_atividade = data
                            for campo, destino in (("input_tokens", "entrada"), ("output_tokens", "saida"), ("cached_input_tokens", "cache")):
                                valor = uso.get(campo)
                                if isinstance(valor, int) and not isinstance(valor, bool) and valor >= 0:
                                    if destino == "entrada":
                                        entrada_sessao += valor
                                    elif destino == "saida":
                                        saida_sessao += valor
                                    else:
                                        cache_sessao += valor

                    rate_limits = payload.get("rate_limits")
                    if not isinstance(rate_limits, dict):
                        continue
                    for nome in limites:
                        valor = limite_valido(rate_limits.get(nome))
                        if valor and (limites[nome] is None or data > limites[nome][0]):
                            limites[nome] = (data, *valor)
        except OSError:
            erros += 1

    usado_sessao, restante_sessao, renova_sessao, estimado_sessao = estado_limite(limites["primary"], agora)
    usado_semana, restante_semana, renova_semana, estimado_semana = estado_limite(limites["secondary"], agora)

    return {
        "sessao": tokens_sessao if eventos_sessao else None,
        "semana": tokens_semana if eventos_semana else None,
        "entrada_5h": entrada_sessao if eventos_sessao else None,
        "saida_5h": saida_sessao if eventos_sessao else None,
        "cache_5h": cache_sessao if eventos_sessao else None,
        "eventos_5h": eventos_sessao,
        "sessoes_5h": len(arquivos_ativos),
        "ultima_atividade": ultima_atividade.isoformat() if ultima_atividade else None,
        "pct_sessao": usado_sessao,
        "pct_semana": usado_semana,
        "pct_restante_sessao": restante_sessao,
        "pct_restante_semana": restante_semana,
        "renova_sessao": renova_sessao,
        "renova_semana": renova_semana,
        "limite_estimado_sessao": estimado_sessao,
        "limite_estimado_semana": estimado_semana,
        "status": "erro" if erros else "ok" if eventos_sessao and eventos_semana and all(limites.values()) else "indisponivel",
        "mensagem": "Erro ao ler sessões" if erros else "Dados indisponíveis" if not eventos_sessao or not all(limites.values()) else None,
        "hora": agora.astimezone().strftime("%H:%M:%S"),
    }


if __name__ == "__main__":
    print(json.dumps(ler_logs(), ensure_ascii=False))
