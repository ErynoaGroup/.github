# leak-guard

Scanner (`scan.sh`), Muster (`patterns.txt`, nur Regex), Selbsttest (`test.sh`) und wiederverwendbarer Workflow (`.github/workflows/leak-guard.yml`).

Exit-Codes: `0` sauber, `1` Treffer, `>=2` Scanner-Fehler (ungültiges Muster, fehlende Datei, kaputte Allowlist). Ausgegeben wird nur `datei:zeile`, nie der Inhalt.

## Allowlist für bewusste Beispiele (`.leak-guard-allow`)

Für absichtliche Test-Beispiele (z. B. Redaction-Fixtures) legt das aufrufende Repo im Root eine Datei `.leak-guard-allow` an (alternativ Pfad über `LEAK_ALLOW_FILE`).

Format, eine Zeile je Treffer:

```
<pfad relativ zum Repo-Root>:<zeilennummer>:<sha256 des Zeileninhalts ohne Zeilenumbruch>  # <Begründung, Pflicht>
```

- Keine Wildcards (`* ? [ ]`), kein Bereich. Ein Verstoß oder eine fehlende Begründung ergibt Exit 2.
- Unterdrückt wird ein Treffer nur, wenn Pfad, Zeilennummer **und** Hash exakt stimmen. Ändert sich die Zeile oder verschiebt sie sich, ist sie wieder ein Treffer, und der Eintrag muss bewusst neu berechnet werden.
- Gilt für Datei- und `--staged`-Scans, nicht für `--stdin` (PR-Text, Commit-Messages).
- Die Datei enthält keine Klartextwerte, nur `pfad:zeile:hash`.

Eintrag berechnen:

```sh
f=tests/test_redact_tsnet.py; n=10
printf '%s:%s:%s  # Redaction-Fixture, synthetische ID\n' "$f" "$n" \
  "$(sed -n "${n}p" "$f" | tr -d '\n' | sha256sum | cut -d' ' -f1)" >> .leak-guard-allow
```

Beispiel: `ErynoaGroup/.atlas` (`tests/test_redact_tsnet.py`, `tests/test_redaction_version.py`).
