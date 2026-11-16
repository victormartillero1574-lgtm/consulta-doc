"""Exporta la base (docs/data/docs.json) a archivos Markdown listos para cargar
como fuentes en NotebookLM.

Un archivo por ambito/tipo (p. ej. "Entre Rios - Jurisprudencia"), partido en
varias partes si supera el limite de palabras por fuente. Cada documento lleva
su URL de SAIJ para poder verificar la cita en la fuente oficial.

Uso:  python3 scripts/exportar_notebooklm.py
"""
import json
import re
import unicodedata
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
ENTRADA = RAIZ / "docs" / "data" / "docs.json"
SALIDA = RAIZ / "docs" / "notebooklm"
# NotebookLM admite hasta 500.000 palabras por fuente; dejamos margen.
MAX_PALABRAS = 400_000


def slug(texto):
    t = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def bloque(d):
    lineas = [f"## {d.get('titulo') or 'Sin titulo'}", ""]
    datos = [
        ("Tipo", d.get("tipo")),
        ("Ambito", d.get("ambito")),
        ("Numero", d.get("numero")),
        ("Caratula", d.get("caratula")),
        ("Fecha", d.get("fecha")),
        ("Provincia", d.get("provincia")),
        ("Materia", d.get("materia")),
        ("Sala", d.get("sala")),
        ("Autores", ", ".join(d.get("autores") or [])),
        ("Descriptores", ", ".join(d.get("descriptores") or [])),
        ("Fuente", d.get("url")),
    ]
    lineas += [f"- **{k}:** {v}" for k, v in datos if v]
    lineas += ["", (d.get("texto") or "").strip(), "", "---", ""]
    return "\n".join(lineas)


def main():
    docs = json.loads(ENTRADA.read_text(encoding="utf-8"))
    grupos = {}
    for d in docs:
        grupos.setdefault((d.get("ambito") or "Otro", d.get("tipo") or "Otro"), []).append(d)

    SALIDA.mkdir(parents=True, exist_ok=True)
    for viejo in SALIDA.glob("*.md"):
        viejo.unlink()

    generados = []
    for (ambito, tipo), lista in sorted(grupos.items()):
        lista.sort(key=lambda d: (d.get("fecha") or d.get("agregado") or ""), reverse=True)
        partes, actual, palabras = [], [], 0
        for d in lista:
            b = bloque(d)
            n = len(b.split())
            if actual and palabras + n > MAX_PALABRAS:
                partes.append(actual)
                actual, palabras = [], 0
            actual.append(b)
            palabras += n
        if actual:
            partes.append(actual)

        for i, parte in enumerate(partes, 1):
            sufijo = f"-parte{i}" if len(partes) > 1 else ""
            nombre = f"{slug(ambito)}-{slug(tipo)}{sufijo}.md"
            titulo = f"{tipo} - {ambito}" + (f" (parte {i})" if len(partes) > 1 else "")
            cabecera = (
                f"# {titulo}\n\n"
                "Fuente: SAIJ (datos publicos). Verificar cada cita en la URL indicada "
                "antes de usarla en un escrito.\n\n"
            )
            (SALIDA / nombre).write_text(cabecera + "\n".join(parte), encoding="utf-8")
            generados.append(nombre)

    print(f"{len(docs)} documentos -> {len(generados)} archivos en {SALIDA.relative_to(RAIZ)}")
    for g in generados:
        print("  ", g)


if __name__ == "__main__":
    main()
