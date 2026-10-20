#!/usr/bin/env python3
"""Test the client through an independent Fast DDS-backed agent and XRCE observer."""
import argparse
from pathlib import Path
import socket
import subprocess
from process import Process


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", required=True, type=Path)
    parser.add_argument("--prefix", required=True, type=Path, help="Independent peers installation")
    parser.add_argument("--logs", required=True, type=Path)
    args = parser.parse_args()
    args.logs.mkdir(parents=True, exist_ok=True)
    directory = Path(__file__).resolve().parent
    observer_exe = args.logs.resolve() / "eprosima-observer"
    subprocess.run(["cc", "-std=c99", "-Wall", "-Wextra", "-Werror",
                    f"-I{args.prefix / 'include'}", str(directory / "observer.c"),
                    str(args.prefix / "lib/libmicroxrcedds_client.a"),
                    str(args.prefix / "lib/libmicrocdr.a"), "-o", str(observer_exe)], check=True)
    # eProsima's CLI cannot report an ephemeral port. Reserve a free candidate;
    # readiness + the observer handshake detect failure if another process wins it.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = str(reservation.getsockname()[1])
    agent = Process([args.prefix / "bin/MicroXRCEAgent", "udp4", "-p", port,
                     "-r", directory / "agent.refs", "-v", "4"],
                    args.logs / "agent.log", ready="running...")
    observer = client = None
    try:
        agent.wait_ready()
        observer = Process([observer_exe, port], args.logs / "observer.log", ready="OBSERVER READY")
        observer.wait_ready()
        client = Process([args.client.resolve(), port], args.logs / "client.log")
        client.finish()
        observer.finish()
        if "COUNTERSTATUS RECEIVED AND VERIFIED" not in "".join(observer.lines):
            raise RuntimeError("Independent observer did not verify the sample")
    finally:
        for process in (client, observer, agent):
            if process:
                process.close()
    print("PASS: independent agent accepts session/creates; independent observer verifies CounterStatus")


if __name__ == "__main__":
    main()
