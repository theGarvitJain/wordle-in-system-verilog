# Wordle in SystemVerilog

A hardware implementation of the word game **Wordle**, built for the
**Zynq UltraScale+ MPSoC** (Xilinx Kria board) as ECE 327 — *Digital Hardware
Systems*, Lab 2.

The puzzle logic — picking the hidden word, scoring each guess letter-by-letter,
counting guesses, and deciding win/lose — runs entirely in the **programmable
logic (PL / FPGA fabric)**. A small C program on the **processing system (PS /
ARM core)** drives the game over a UART terminal: it reads your guesses, hands
them to the hardware through AXI-GPIO registers, and prints the colored result.

## How the game works

Standard 4-letter Wordle:

- The hardware holds **1024 four-letter words** in a ROM. Each game picks one as
  the hidden answer.
- You get up to **6 guesses**. For each guess, every letter is scored:
  - **GREEN** — correct letter in the correct position
  - **YELLOW** — letter is in the word but in the wrong position
  - **GREY** — letter is not in the word (in the remaining unmatched letters)
- Win by guessing the word; lose if you run out of guesses.

Scoring follows the standard two-pass rule so duplicate letters are handled
correctly: greens are matched first and "consume" the matching answer letter,
then yellows are matched against whatever answer letters are left. If a guess has
more copies of a letter than the answer does, the extra copies score grey.

## Repository layout

| File | Role |
|------|------|
| [`wordle_top.sv`](wordle_top.sv) | Top-level module — wires the ROM to the FSM. This is the IP packaged into the block design. |
| [`wordle_fsm.sv`](wordle_fsm.sv) | The game's finite state machine: latches guesses, scores them, tracks guess count, decides win/lose. |
| [`wordle_rom.sv`](wordle_rom.sv) | Synchronous 1024×32-bit ROM holding the dictionary (one 4-letter ASCII word per entry). |
| [`wordle_top_tb.sv`](wordle_top_tb.sv) | Self-checking testbench with hand-computed golden results covering wins, losses, duplicates, and game restarts. |
| [`hello_word.c`](hello_word.c) | PS-side C application (the `helloworld.c` baremetal app) that runs the interactive game over UART. |
| [`create_system.tcl`](create_system.tcl) | Vivado Tcl script that builds the block design (Zynq PS + Wordle IP + 7 AXI-GPIO blocks). |
| [`constraints.xdc`](constraints.xdc) | Timing constraint — defines the 100 MHz PL clock. |
| [`wordle_design_wrapper.xsa`](wordle_design_wrapper.xsa) | Exported hardware handoff (bitstream + hardware description) for Vitis. |

## Hardware interface

`wordle_top` exposes the following ports (parameters in brackets are the
defaults: 4 letters, 6 guesses, 1024-word dictionary):

**Inputs**
- `clk`, `rstn` — clock and active-low reset
- `i_ref_word_idx` `[9:0]` — ROM index selecting the hidden word for this game
- `i_guess_word` `[31:0]` — the guess, packed as 4 ASCII bytes (letter 0 = MSB)
- `i_guess_id` `[3:0]` — incremented for each new guess; dropping it back to 0 starts a new game

**Outputs**
- `o_ready` — high when the FSM is idle and ready to accept a new guess
- `o_result` `[7:0]` — 4 letters × 2-bit status; letter 0 in the most-significant pair (`[7:6]`)
- `o_guess_count` `[3:0]` — number of guesses made so far
- `o_game_status` `[1:0]` — `00` ongoing, `11` win, `10` lose

Status/color encodings: `GREY=00`, `GREEN=01`, `YELLOW=10`; `ONGOING=00`,
`LOSE=10`, `WIN=11`.

### Word packing convention

A word is packed so **letter 0 (leftmost) is the most-significant byte**, e.g.
`"skim"` → `0x736b696d`. The result is packed the same way, so reading a result
byte left-to-right matches the word left-to-right (and matches what the C
program prints over UART).

## FSM operation

`wordle_fsm` runs a 5-state machine (`RST → WAITING → PROCESS → LATCH → DONE`):

1. **WAITING** — `o_ready` is high. When `i_guess_id` increments, the new guess
   word, its id, and the current reference word are registered, and the FSM
   moves to PROCESS.
2. **PROCESS** — one settle cycle. The result is computed combinationally
   (green pass, then yellow pass) from the registered guess and reference word.
3. **LATCH** — the computed result, guess count, and game status are committed to
   registers. The win/lose decision is made here.
4. **DONE** — reached on win or loss; `o_ready` stays low. When the driver sets
   `i_guess_id` back to 0, the FSM restarts a fresh game.

The two-cycle PROCESS→LATCH path guarantees the guess data is stable for a full
cycle before it is consumed, avoiding a same-edge race against the synchronous
ROM read.

## Software flow (PS side)

[`hello_word.c`](hello_word.c) talks to the seven AXI-GPIO blocks created in the
Tcl script. Each game loop:

1. Picks a random puzzle ID (`rand() % 1024`) and writes it to `ref_word_idx`.
2. Prompts `Enter guess:`, reads 4 characters, lowercases them, packs them into a
   32-bit word, and writes the guess plus an incremented `guess_id`.
3. Waits on the `ready` handshake, reads back the `result` and `guess_count`, and
   prints the per-letter outcome (`G` / `Y` / `X`).
4. On win/lose, prints the end message and resets `guess_id` to 0 to begin a new
   game.

UART runs at **115200 baud** (PS7 UART, configured by the bootrom/BSP).

## Build & run

This targets the Xilinx Vivado/Vitis flow on a Zynq UltraScale+ board.

1. **Hardware (Vivado).** Create a project with `wordle_top.sv`, `wordle_fsm.sv`,
   and `wordle_rom.sv`; package `wordle_top` as IP. Source
   [`create_system.tcl`](create_system.tcl) to build the block design (Zynq PS,
   the Wordle IP, and the AXI-GPIO blocks), apply
   [`constraints.xdc`](constraints.xdc), then generate the bitstream and export
   the hardware (`wordle_design_wrapper.xsa`).
2. **Software (Vitis).** Create a platform from the `.xsa`, add a baremetal
   application, and use [`hello_word.c`](hello_word.c) as the main source.
3. **Play.** Program the board, open a serial terminal (e.g. PuTTY) at 115200
   baud, and follow the prompts.

## Simulation

Simulate the design with [`wordle_top_tb.sv`](wordle_top_tb.sv) (e.g. in Vivado's
simulator or any SystemVerilog simulator). The testbench is fully self-checking:
golden results for each test are computed by hand from the ROM contents, so a
buggy DUT cannot mask its own error. It exercises straight wins, all-grey guesses,
mixed green/yellow/grey, duplicate letters in the guess and/or answer, the
last-occurrence yellow rule, losing after 6 guesses, winning on a later guess, and
restarting a finished game. It prints `TEST PASSED!` or `TEST FAILED!` along with a
per-check tally.
