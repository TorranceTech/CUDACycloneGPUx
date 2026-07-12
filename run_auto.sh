#!/usr/bin/env bash
#
# run_auto.sh — mantém o CUDACyclone rodando 24/7, reinicia se travar,
#               e PARA na hora se achar a chave (salvando tudo em arquivo).
#
# Uso:   ./run_auto.sh
# Parar: Ctrl-C  (ou: pkill -f run_auto.sh)
#
# -------- CONFIGURAÇÃO (edite aqui) --------------------------------
RANGE="666666666666666666:7FFFFFFFFFFFFFFFFF"          # fatia 60%->100% do puzzle 71
ADDRESS="1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU"           # CONFIRME que é o endereço certo!
GRID="128,128"                                          # bom meio-termo pras 2 GPUs
EXTRA_ARGS="--random"                                   # modo lottery (pulo aleatório)
RESTART_DELAY=5                                         # segundos de espera antes de reiniciar
# NÃO defina CUDA_VISIBLE_DEVICES: assim ele usa a 3060 + a 1070 juntas.
# ------------------------------------------------------------------

cd "$(dirname "$0")" || exit 1
BIN="./CUDACyclone"
LOGDIR="./logs"
mkdir -p "$LOGDIR"
RUNLOG="$LOGDIR/run_$(date +%Y%m%d_%H%M%S).log"
FOUNDFILE="./ACHOU_A_CHAVE.txt"

if [[ ! -x "$BIN" ]]; then
    echo "ERRO: $BIN não encontrado ou não executável. Rode 'make' primeiro." >&2
    exit 1
fi

# Encerramento limpo no Ctrl-C: mata o solver (e qualquer filho) e sai.
CHILD=""
kill_tree() {
    local pid=$1
    [[ -z "$pid" ]] && return
    pkill -TERM -P "$pid" 2>/dev/null   # filhos do solver
    kill  -TERM "$pid"    2>/dev/null   # o solver
    # espera até 3s por saída limpa; senão SIGKILL
    for _ in 1 2 3; do kill -0 "$pid" 2>/dev/null || return; sleep 1; done
    pkill -KILL -P "$pid" 2>/dev/null
    kill  -KILL "$pid"    2>/dev/null
}
cleanup() {
    echo ""
    echo "[$(date '+%H:%M:%S')] Parando por pedido do usuário..."
    kill_tree "$CHILD"
    exit 0
}
trap cleanup INT TERM

echo "=================================================================="
echo " CUDACyclone auto-restart"
echo " Range   : $RANGE"
echo " Address : $ADDRESS"
echo " Grid    : $GRID   Args: $EXTRA_ARGS"
echo " Log     : $RUNLOG"
echo " Início  : $(date '+%Y-%m-%d %H:%M:%S')"
echo " (Ctrl-C para parar)"
echo "=================================================================="

START_TS=$(date +%s)
attempt=0

while true; do
    attempt=$((attempt + 1))
    echo "[$(date '+%H:%M:%S')] Tentativa #$attempt — iniciando busca..." | tee -a "$RUNLOG"

    # Roda o solver; a saída vai pra tela E pro log ao mesmo tempo.
    # Process substitution (> >(tee)) mantém $! = PID do SOLVER (não do tee),
    # então 'wait' pega o código de saída real e o Ctrl-C mata o solver de verdade.
    stdbuf -oL "$BIN" --range "$RANGE" --address "$ADDRESS" --grid "$GRID" $EXTRA_ARGS \
        > >(tee -a "$RUNLOG") 2>&1 &
    CHILD=$!
    wait "$CHILD"
    rc=$?
    CHILD=""

    # ---- ACHOU A CHAVE? (o mais importante) ----
    if grep -q "FOUND MATCH" "$RUNLOG"; then
        {
            echo "############### CHAVE ENCONTRADA ###############"
            echo "Quando : $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Uptime : $(( ($(date +%s) - START_TS) / 3600 ))h"
            echo "-----------------------------------------------"
            grep -A6 "FOUND MATCH" "$RUNLOG"
        } | tee "$FOUNDFILE"
        echo ""
        echo ">>> Salvo em: $FOUNDFILE  (e no log: $RUNLOG)"
        echo ">>> Parei de reiniciar. NÃO feche antes de copiar a chave!"
        # bipe no terminal, se suportar
        for _ in 1 2 3 4 5; do printf '\a'; sleep 1; done
        exit 0
    fi

    # ---- Não achou: foi crash ou parada. Reinicia. ----
    UPH=$(( ($(date +%s) - START_TS) / 3600 ))
    echo "[$(date '+%H:%M:%S')] Solver saiu (código $rc). Uptime total: ${UPH}h. Reiniciando em ${RESTART_DELAY}s..." | tee -a "$RUNLOG"
    sleep "$RESTART_DELAY"
done
