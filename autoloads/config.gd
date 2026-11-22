extends Node

# Gateway. Usa 127.0.0.1 y NO "localhost": Compose publica solo en loopback IPv4 y
# "localhost" puede resolverse a ::1 y no conectar (guía §1.1).
# Modo LAN (guía §1.4): serían https://<IP>:8443 y wss://<IP>:8443/api/game/ws, con el ca.crt
# del anfitrión verificado por huella y TLSOptions.client(ca). No está implementado todavía.
const BASE_URL = "http://127.0.0.1:8080" #gateway
const WS_URL = "ws://127.0.0.1:8080/api/game/ws"   # wss:// bajo TLS
