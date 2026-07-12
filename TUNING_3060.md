# Tuning CUDACyclone — RTX 3060 + GTX 1070 (medido em 2026-07-01, Linux, CUDA 12.0)

Todos os números medidos na faixa do puzzle 71 (`400000000000000000:7fffffffffffffffff`),
média de ~10s de regime, descartando os 2 primeiros segundos.

## Resumo executivo
- **RTX 3060 sozinha, melhor config: `--grid 128,64` → ~970-980 Mkeys/s.**
- **Usar as DUAS GPUs (padrão, sem CUDA_VISIBLE_DEVICES): ~1.18 Gkeys/s agregado.**
- Cobertura completa confirmada em `128,64` (acha a chave num sweep 100%). Sem key-skipping.
- **Não existe ganho de 5x aqui** — o kernel é maduro e limitado pelo hardware. Detalhes abaixo.

## Benchmark de grid na RTX 3060
| grid (pontos,threads) | Mkeys/s |
|-----------------------|---------|
| 64,64  (era o usado)  | ~930    |
| 96,96                 | ~949    |
| 64,128                | ~927    |
| **128,64**            | **~968-978** |
| 128,128               | ~893    |
| 256,256               | ~613    |
| 512,256               | ~372    |
| 1024,256              | ~409    |

→ Na 3060, **batch de pontos PEQUENO ganha**. O array por-thread `subp[]` é dimensionado
por `MAX_BATCH_SIZE`; batches grandes estouram o stack frame (24 KB/thread a 1536), derrubando
occupancy. É o oposto da 4090, que tem cache/occupancy de sobra.

## GTX 1070 (Pascal, compute 6.1)
- Melhor: `--grid 256,128` → ~287 Mkeys/s sozinha. Pascal prefere batch GRANDE (oposto da 3060).
- Rodando junto com a 3060, cai para ~210 Mkeys/s por contenção de host/PCIe.

## Dual-GPU
- Modo multi-GPU embutido (rodar `./CUDACyclone` sem fixar device) divide a faixa e usa as duas.
- `--grid 128,128` deu ~1.18 Gkeys/s agregado. Um único `--grid` não é ótimo pras duas
  simultaneamente (3060 quer 128, 1070 quer 256), mas o ganho de ligar a 1070 ociosa é real (~+20%).

## O que foi testado e NÃO ajudou (não aplicado)
- **Remover `-rdc=true` + inline do `getHash160_33_from_limbs`**: saiu ~1% mais LENTO (965 vs 978).
  O `__noinline__` na função de hash é proposital e correto — inlining aumenta pressão de
  registrador e perde mais occupancy do que economiza em overhead de chamada.
- **`MAX_BATCH_SIZE` 1536→512**: ganho ~1% (dentro do ruído), reduz memória, mas mexe em
  memória constante. Não vale o risco dado o histórico de bug de key-skipping do projeto. Revertido.

## Por que 5x é impossível aqui
Puzzle 71 é busca por hash160 (a pubkey só é revelada quando um output é gasto), então
BSGS/kangaroo NÃO se aplicam — é força bruta pura. O único número que importa é keys/s bruto,
limitado pelo silício. A matemática já é PTX otimizado à mão (herança do VanitySearch). 5x só
com hardware diferente (GPUs mais novas/mais GPUs).
