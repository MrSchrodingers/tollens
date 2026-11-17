#!/usr/bin/env python3
"""Gerador de mutantes de evidence/hooks/model-honor.sh (ADR 0048, regra 3 do ADR 0015).

Uso: gen.py <diretorio_de_saida> <caminho_do_hook>

Escreve um arquivo `m_<ID>.sh` por mutante (o hook com UMA troca textual) e a lista
`equivalentes.txt`. Cada troca tem uma ancora que precisa existir no hook; ancora ausente
vira erro (exit 1), para o mutante nao sumir em silencio quando o hook mudar.

Mutantes EQUIVALENTES (sobrevivem por construcao, e isso e esperado):
  G4_trap           todo caminho do modo hook termina com `exit 0` explicito e nao ha `set -e`
                    (NAO VERIFICADO: nenhuma entrada que provoque erro interno foi encontrada).
  U_msgcap          os tetos por campo (40 e 80) impedem que o teto de 300 seja atingido.
`W_roottranscript` NAO e equivalente: transcript fora das raizes com meta symlink para dentro
(caso 46 da suite) o mata. `SYN_sintaxe` e o controle do executor: deve ficar inconclusivo.
"""
import pathlib
import sys

EQUIVALENTES = ["G4_trap", "U_msgcap"]
M = {
 'A_pai': ('((.agent_transcript_path | c(4096)) // "")', '(((.agent_transcript_path // .transcript_path) | c(4096)) // "")'),
 'B_rot': ('if [ "$SZ" -gt 2097152 ]; then', 'if false; then'),
 'B2_rotlim': ('-gt 2097152 ]', '-gt 209715200 ]'),
 'B3_noflock': ('if flock -w 5 9; then', 'if true; then'),
 'B4_noflockcmd': ('      if command -v flock >/dev/null 2>&1; then', '      if false; then'),
 'C_caps': ('head -c 1048576 "$rp"', 'cat "$rp"'),
 'C2_lin4': ('head -n 400 |', 'head -n 4 |'),
 'C3_lin4000': ('head -n 400 |', 'head -n 4000 |'),
 'D_fam': ('if [ "$FAM" = "$PN" ]; then STATUS=honrado', 'if [[ "$EN" == *"$PN"* ]]; then STATUS=honrado'),
 'D2_fam_token': ('if [ "$FAM" = "$PN" ]; then STATUS=honrado', 'if [[ "$EN" == claude-"$PN"-* ]]; then STATUS=honrado'),
 'E_case': ('local v="${1,,}"', 'local v="$1"'),
 'E2_case_alias': ('pl="${PEDIDO,,}"', 'pl="$PEDIDO"'),
 'F_san': ('def c($n): strings | gsub("[[:cntrl:]]"; "") | .[0:$n];', 'def c($n): strings | .[0:$n];'),
 'F2_trunc': ('def c($n): strings | gsub("[[:cntrl:]]"; "") | .[0:$n];', 'def c($n): strings | gsub("[[:cntrl:]]"; "");'),
 'V_pfcap': ('(.agent_type | c(256))', '(.agent_type | c(100000))'),
 'G_meta': ('head -c 65536 "$mrp"', 'cat "$mrp"'),
 'I_since': ('[ "$MT" -lt "$SINCE_EP" ]', '[ "$MT" -le "$SINCE_EP" ]'),
 'K_idpref': ('[ "$PN" = "$EN" ]', '[[ "$EN" == "$PN"* ]]'),
 'L_scanall': ('-mindepth 4 -maxdepth 4', '-mindepth 4 -maxdepth 6'),
 'N_nojqmsg': ("  printf '%s\\n' '{\"systemMessage\":\"model-honor: verificacao de modelo desligada, jq ausente\"}'\n", ''),
 'O_ascii': ('linha="$(jq -nac', 'linha="$(jq -nc'),
 'P_logerr': ('if [ "$rc" -ne 0 ]; then', 'if false; then'),
 'Q_scan0': ('[ "$ACHADOS" -eq 0 ] && [ "${CNT[ilegivel]:-0}" -eq 0 ]', '[ "$ACHADOS" -eq -1 ]'),
 'R_probe': ('if [ "$(jq -n \'1 + 1\' 2>/dev/null)" != 2 ]; then', 'if false; then'),
 'S_type': ('else "<tipo_invalido:" + type + ">" end;', 'else "" end;'),
 'T_path': ('MP="$(limpa "$M")"', 'MP="$M"'),
 'U_msgcap': ('{systemMessage: .[0:300]}', '{systemMessage: .}'),
 'W_roottranscript': ('if ! sob_raiz "$rp"; then', 'if false; then'),
 'X_picked': ('--arg pk "$PICKED"', '--arg pk ""'),
 'Y_origem': ('if [ "$META_OK" -eq 1 ] && [ -n "$PEDIDO" ]; then ORIGEM=meta; fi', ':'),
 'Z_synth': ('select(. != "<synthetic>" and . != "")', 'select(. != "")'),
 'mA_raizirma': ('case "$p" in "$r"/*) return 0 ;; esac', 'case "$p" in "$r"*) return 0 ;; esac'),
 'mB_attype': ('AT="${AT:-$META_TYPE}"', 'AT="$AT"'),
 'G1_realpath': ('rp="$(realpath -m -- "$tp" 2>/dev/null)"', 'rp="$tp"'),
 'G2_efetnorm': ('EN="$(norm_id "$EFETIVO")"', 'EN="$EFETIVO"'),
 'G3_cntrl_efet': ('| gsub("[[:cntrl:]]"; "") | .[0:257]\'', '| .[0:257]\''),
 'G4_trap': ("trap 'exit 0' EXIT", ':'),
 'G5_mkdir': ('mkdir -p "$(dirname "$LOG")" || exit 1', ':'),
 'G6_claude': ('if [[ "$EN" == claude-* ]]; then\n        if [ "$FAM"', 'if true; then\n        if [ "$FAM"'),
 'M5_id': ('elif [[ "$EN" == claude-* ]]; then STATUS=DIVERGE; MOTIVO=id_diferente', 'elif false; then STATUS=DIVERGE; MOTIVO=id_diferente'),
 'D2_derivada': ('elif [ -n "$FAM" ] && [ "$FAM" != "$PN" ]; then', 'elif false; then'),
 'D2_fam_id': ('if [ -n "$FAM" ] && [ -n "$FE" ] && [ "$FAM" != "$FE" ]; then', 'if false; then'),
 'D2_segmento': ('v="${v##*/}"', ':'),
 'D2_pontos': ('printf \'%s\' "${v//./-}"', 'printf \'%s\' "$v"'),
 'D2_tokenclaude': ('[ "$tem_claude" -eq 1 ] || return 0', ':'),
 'D3_nenhum': ('if [ "$TOTAL" -gt 0 ] && [ $(( ${CNT[honrado]:-0} + ${CNT[DIVERGE]:-0} )) -eq 0 ]; then', 'if false; then'),
 'SYN_sintaxe': ('MODO=hook\n', 'MODO=hook\nif\n'),
 'M1_exit3': ('[ "$NJ" -gt 0 ] && return 3', ':'),
 'M1_pd': ('+ ${CNT[pedido_desconhecido]:-0} ))', '+ 0 ))'),
 'M1_resumo': ('echo "model-honor: NAO JULGADOS $NJ de $TOTAL', 'echo "model-honor: JULGADOS $NJ de $TOTAL'),
 'M2_escape': ('|| [ "$MOTIVO" = caminho_fora_da_raiz ]; then', '; then'),
 'N1_noperl': ('if [ "$RCJ" -ne 0 ] && command -v perl >/dev/null 2>&1; then', 'if false; then'),
 'N2_perlbarra': ("s{(\\\\\\\\)|", "s{(ZZZZ)|"),
 'J1_jqerro': ('controle_filtros || ST=jq_erro', 'controle_filtros || true'),
 'J2_ileg': ('CNT[ilegivel]=$(( ${CNT[ilegivel]:-0} + N ))', 'CNT[ilegivel]=$(( ${CNT[ilegivel]:-0} + 0 ))'),
 'J3_exit2': ('o resultado nao vale" >&2\n    return 2', 'o resultado nao vale" >&2\n    return 0'),
 'P1_par': ('if [ "$TOTAL" -gt 0 ]; then', 'if true; then'),
 'P2_exitscan': ('scan_main "$@"\n  exit $?', 'scan_main "$@"'),
 'IL1_idlongo': ('[ "${#PEDIDO}" -gt 256 ]', '[ "${#PEDIDO}" -gt 25600 ]'),
 'R1_gen2': ('[ -e "$LOG.1" ] && mv -f "$LOG.1" "$LOG.2"', ':'),
 'R2_gen3': ('[ -e "$LOG.2" ] && mv -f "$LOG.2" "$LOG.3"', ':'),
 'RF1_rotfield': ('command -v flock >/dev/null 2>&1 || rot=sem_flock', ':'),
 'LM1_2028': ("v=\"${v//$'\\xe2\\x80\\xa8'/ }\"", ':'),
 'LM2_cntrl': ('v="${v//[[:cntrl:]]/ }";', ''),
 'NO1_data': ('[[ "$v" =~ $re_d ]] && v="${BASH_REMATCH[1]}"', ':'),
 'NO2_bedrock': ('[[ "$v" =~ $re_v ]] && v="${BASH_REMATCH[1]}"', ':'),
 'NO3_at': ('[[ "$v" =~ $re_at ]] && v="${BASH_REMATCH[1]}"', ':'),
 'NO4_regiao': ("re_pf='^([a-z]+\\.)?anthropic\\.(.*)$'", "re_pf='^([a-z]{2}\\.)?anthropic\\.(.*)$'"),
 'NO5_umcolchete': ('while [[ "$v" =~ $re_br ]]; do v="${BASH_REMATCH[1]}"; done', 'if [[ "$v" =~ $re_br ]]; then v="${BASH_REMATCH[1]}"; fi'),
 'NO6_pedidonorm': ('PN="$(norm_id "$PEDIDO")"', 'PN="$PEDIDO"'),
 'HK1_jqbroken_hook': ("printf '%s\\n' '{\"systemMessage\":\"model-honor: verificacao de modelo desligada, jq nao funciona\"}'\n  exit 0", "exit 0"),
 'IL2_ilegivel_msg': ('ILL="payload ilegivel (${PBYTES} bytes, sha256 ${PSHA})"', 'ILL=""'),
 'IL3_sha': ('PSHA="$(printf \'%s\' "$IN" | sha256sum 2>/dev/null | cut -c1-12)"', 'PSHA=""'),
 'AR1_arqileg': ('if [ ! -r "$mrp" ]; then STATUS=indeterminado; MOTIVO=arquivo_ilegivel; return 0; fi', ':'),
 'D1_ctrl': ('if ! controle_filtros; then', 'if false; then'),
 'D2_mult': ("if [[ \"$TIPO\" == *$'\\n'* ]]; then", 'if false; then'),
 'D2c_campo': ('{payload_multiplo: true}', '{}'),
 'D4_findL': ('find -L "$DIR"', 'find "$DIR"'),
 'D4_links': ('for d in "$DIR"/* "$DIR"/*/*; do', 'for d in; do'),
 'D4_quebrado': ('else QUEBRADOS=$((QUEBRADOS + 1)); fi', 'else :; fi'),
 'D4_cnt': ('CNT[ilegivel]=$(( ${CNT[ilegivel]:-0} + QUEBRADOS ))', ':'),
 'D5_since': ('if [ "$HAS_SINCE" = 1 ] && [ -z "$SINCE" ]; then', 'if false; then'),
 'D3_latest': ('[[ "$v" =~ $re_l ]] && v="${BASH_REMATCH[1]}"', ':'),
 'mx1_controle_efet': ("    && [ \"$(printf '%s\\n' '{\"type\":\"assistant\",\"message\":{\"model\":\"claude-x\"}}' | jq_efet)\" = claude-x ]", '    && true'),
 'D1b_extracao': ('if [ "${#PF[@]}" -ne 4 ]; then', 'if false; then'),
 'D2d_naoobjeto': ('select((.agent_transcript_path | type) == "string")', 'select(true)'),
 'D2e_semcaminho': ('if [ -z "$SEL" ]; then', 'if false; then'),
 'R3_foraraiz': ('arquivo_ilegivel|caminho_fora_da_raiz) ST=ilegivel ;;', 'arquivo_ilegivel) ST=ilegivel ;;'),
}

def main() -> int:
    saida = pathlib.Path(sys.argv[1])
    fonte = pathlib.Path(sys.argv[2]).read_text()
    saida.mkdir(parents=True, exist_ok=True)
    ausentes = []
    for nome, (antigo, novo) in M.items():
        if fonte.count(antigo) < 1:
            ausentes.append(nome)
            continue
        (saida / f"m_{nome}.sh").write_text(fonte.replace(antigo, novo, 1))
    (saida / "equivalentes.txt").write_text("\n".join(EQUIVALENTES) + "\n")
    if ausentes:
        print("ANCORA NAO ENCONTRADA:", " ".join(ausentes), file=sys.stderr)
        return 1
    print(len(M), "mutantes gerados")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
