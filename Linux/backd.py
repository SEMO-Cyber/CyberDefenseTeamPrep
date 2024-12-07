import psutil

def network_monitor():
    processes = psutil.net_connections(kind="inet")

    for process in processes:
        if process.status == "ESTABLISHED" and process.raddr.ip != "127.0.0.1":
            print("================================================")
            print("Connection found")
            get_process_details(process.pid)
            print(f"Remote IP: {process.raddr.ip}")

def get_process_details(pid):
    try:
        process = psutil.Process(pid)
        print(f"[+] Process Name: {process.name()}")
        print(f"[+] Process PID: {process.pid}")
        print(f"[+] Process Status: {process.status()}")
    except psutil.NoSuchProcess:
        print(f"No process found with PID {pid}")
    except psutil.AccessDenied:
        print(f"Access denied to process with PID {pid}")

if __name__ == '__main__':
    network_monitor()