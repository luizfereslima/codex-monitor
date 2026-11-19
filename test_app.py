import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import app
import usage


class LeituraSessoesTest(unittest.TestCase):
    def setUp(self):
        self.pasta = tempfile.TemporaryDirectory()
        self.addCleanup(self.pasta.cleanup)
        self.agora = datetime.now(timezone.utc)
        self.arquivo = Path(self.pasta.name) / "sessao.jsonl"

    def evento(self, horas, total=None, acumulado=None, primary=None, secondary=None,
               entrada=None, saida=None, cache=None):
        info = {}
        if total is not None:
            uso = {"total_tokens": total}
            for chave, valor in (("input_tokens", entrada), ("output_tokens", saida), ("cached_input_tokens", cache)):
                if valor is not None:
                    uso[chave] = valor
            info["last_token_usage"] = uso
        if acumulado is not None:
            info["total_token_usage"] = {"total_tokens": acumulado}
        return {
            "timestamp": (self.agora - timedelta(hours=horas)).isoformat(),
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "info": info,
                "rate_limits": {
                    "primary": {"used_percent": primary, "resets_at": 1800000000} if primary is not None else None,
                    "secondary": {"used_percent": secondary, "resets_at": 1800000000} if secondary is not None else None,
                },
            },
        }

    def escrever(self, *eventos, parcial=""):
        self.arquivo.write_text("".join(json.dumps(evento) + "\n" for evento in eventos) + parcial)

    def ler(self):
        with patch.object(usage, "PASTA_SESSIONS", self.pasta.name):
            return usage.ler_logs(self.agora)

    def test_soma_apenas_incrementos_e_usa_limite_mais_recente(self):
        self.escrever(
            self.evento(6, 10, 10, 80, 25),
            self.evento(2, 20, 30, 12, 26, entrada=15, saida=5, cache=10),
            self.evento(1, 5, 35, 13, 27, entrada=4, saida=1, cache=2),
            parcial='{"type":"event_msg","payload":',
        )
        dados = self.ler()
        self.assertEqual((dados["sessao"], dados["semana"]), (25, 35))
        self.assertEqual((dados["pct_sessao"], dados["pct_semana"]), (13, 27))
        self.assertEqual((dados["pct_restante_sessao"], dados["pct_restante_semana"]), (87, 73))
        self.assertEqual(dados["status"], "ok")
        self.assertEqual(dados["renova_sessao"], "2027-01-15T08:00:00+00:00")
        self.assertEqual((dados["entrada_5h"], dados["saida_5h"], dados["cache_5h"]), (19, 6, 12))
        self.assertEqual((dados["eventos_5h"], dados["sessoes_5h"]), (2, 1))
        self.assertEqual(dados["ultima_atividade"], (self.agora - timedelta(hours=1)).isoformat())

    def test_evento_incompleto_nao_remove_dados_validos(self):
        self.escrever(self.evento(1, 7, primary=42, secondary=31), self.evento(0.5))
        dados = self.ler()
        self.assertEqual(dados["sessao"], 7)
        self.assertEqual(dados["pct_sessao"], 42)
        self.assertEqual(dados["status"], "ok")

    def test_limite_expirado_renova_sem_novo_evento(self):
        evento = self.evento(1, 7, primary=100, secondary=80)
        evento["payload"]["rate_limits"]["primary"]["resets_at"] = self.agora.timestamp() - 1
        self.escrever(evento)
        dados = self.ler()
        self.assertEqual(dados["pct_restante_sessao"], 100)
        self.assertTrue(dados["limite_estimado_sessao"])
        self.assertIsNone(dados["renova_sessao"])
        self.assertEqual(dados["pct_restante_semana"], 20)
        self.assertFalse(dados["limite_estimado_semana"])

    def test_novo_evento_substitui_renovacao_estimada(self):
        antigo = self.evento(1, 7, primary=100, secondary=80)
        antigo["payload"]["rate_limits"]["primary"]["resets_at"] = self.agora.timestamp() - 1
        novo = self.evento(0, 2, primary=4, secondary=81)
        self.escrever(antigo, novo)
        dados = self.ler()
        self.assertEqual(dados["pct_restante_sessao"], 96)
        self.assertFalse(dados["limite_estimado_sessao"])
        self.assertIsNotNone(dados["renova_sessao"])

    def test_sem_dados_e_sem_pasta(self):
        self.assertEqual(self.ler()["status"], "indisponivel")
        with patch.object(usage, "PASTA_SESSIONS", str(Path(self.pasta.name) / "ausente")):
            dados = usage.ler_logs(self.agora)
        self.assertEqual(dados["status"], "erro")
        self.assertIsNone(dados["sessao"])

    def test_api_uso(self):
        self.escrever(self.evento(1, 9, primary=17, secondary=29))
        with patch.object(usage, "PASTA_SESSIONS", self.pasta.name):
            resposta = app.app.test_client().get("/api/uso")
        self.assertEqual(resposta.status_code, 200)
        self.assertEqual(resposta.json["sessao"], 9)
        self.assertEqual(resposta.json["pct_sessao"], 17)
        self.assertEqual(resposta.json["pct_restante_sessao"], 83)


if __name__ == "__main__":
    unittest.main()
