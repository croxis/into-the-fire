"""UDP proxy that delays (and optionally drops / jitters) packets both ways.

python3 tests/lag/lag_proxy.py LISTEN_PORT SERVER_PORT LATENCY_MS [JITTER_MS] [LOSS_PERCENT]
One-way latency, so ping is twice LATENCY_MS. Jitter is uniform +/-, and can
reorder packets, as the real internet can.
"""
import heapq, random, select, socket, sys, time

listen_port, server_port, latency = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]) / 1000
jitter = float(sys.argv[4]) / 1000 if len(sys.argv) > 4 else 0.0
loss = float(sys.argv[5]) / 100 if len(sys.argv) > 5 else 0.0

front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
front.bind(("127.0.0.1", listen_port))
back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
back.connect(("127.0.0.1", server_port))
client = None
queue = []  # (due, seq, socket, data, addr)
seq = 0


def schedule(sock, data, addr):
    global seq
    if random.random() < loss:
        return
    due = time.monotonic() + max(0.0, latency + random.uniform(-jitter, jitter))
    heapq.heappush(queue, (due, seq, sock, data, addr))
    seq += 1


while True:
    timeout = max(0.0, queue[0][0] - time.monotonic()) if queue else 0.05
    ready, _, _ = select.select([front, back], [], [], min(timeout, 0.05))
    for s in ready:
        if s is front:
            data, client = front.recvfrom(65536)
            schedule(back, data, None)
        elif client:
            schedule(front, back.recv(65536), client)
    now = time.monotonic()
    while queue and queue[0][0] <= now:
        _, _, sock, data, addr = heapq.heappop(queue)
        sock.send(data) if addr is None else sock.sendto(data, addr)
