#!/usr/bin/env python3
"""Cliente de sonda para verif/scripts/TC-012.sh.

Envía bytes a un socket Unix de forma controlada (completo, byte a byte o en
particiones aleatorias) y vuelca la respuesta recibida en stdout. Los metadatos
de la conexión se escriben en stderr como pares clave=valor.

Código de salida: 0 = conexión establecida, 2 = no se pudo conectar.
"""
import argparse
import random
import socket
import sys
import time


def split(data, mode, seed):
    if mode == "whole":
        return [data]
    if mode == "byte":
        return [data[i:i + 1] for i in range(len(data))]
    rng = random.Random(seed)
    out, i = [], 0
    while i < len(data):
        n = rng.randint(1, 5)
        out.append(data[i:i + n])
        i += n
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--socket", required=True)
    ap.add_argument("--payload-file", required=True)
    ap.add_argument("--chunk", choices=["whole", "byte", "random"], default="whole")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--delay", type=float, default=0.01,
                    help="pausa entre fragmentos (s)")
    ap.add_argument("--eof", action="store_true",
                    help="cerrar la escritura tras enviar")
    ap.add_argument("--idle", type=float, default=2.0,
                    help="segundos sin datos tras los que se deja de esperar; "
                         "0 = no leer la respuesta (cerrar tras enviar)")
    ap.add_argument("--max-read", type=int, default=65536)
    a = ap.parse_args()

    with open(a.payload_file, "rb") as f:
        data = f.read()

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(a.idle if a.idle > 0 else 2.0)
    try:
        s.connect(a.socket)
    except OSError as e:
        print(f"connect_error={e}", file=sys.stderr)
        return 2

    sent, send_error = 0, ""
    for chunk in split(data, a.chunk, a.seed):
        try:
            s.sendall(chunk)
            sent += len(chunk)
        except OSError as e:  # el servicio pudo rechazar y cerrar antes de terminar
            send_error = type(e).__name__
            break
        if a.chunk != "whole" and a.delay:
            time.sleep(a.delay)

    if a.eof and not send_error:
        try:
            s.shutdown(socket.SHUT_WR)
        except OSError:
            pass

    resp, closed, read_error = b"", False, ""
    while a.idle > 0 and len(resp) < a.max_read:
        try:
            part = s.recv(4096)
        except socket.timeout:
            break
        except OSError as e:
            read_error = type(e).__name__
            break
        if not part:
            closed = True
            break
        resp += part

    sys.stdout.buffer.write(resp)
    sys.stdout.buffer.flush()
    print(f"sent={sent}/{len(data)} send_error={send_error or 'none'} "
          f"closed_by_peer={int(closed)} read_error={read_error or 'none'} "
          f"response_bytes={len(resp)}", file=sys.stderr)
    s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
