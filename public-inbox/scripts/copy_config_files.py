import os
import time
import subprocess

directory = "/data"  # Replace with the actual path
filename = "/config/config_result"  # File to append the raw content to
hostname = "lore.kernel.ime.usp.br"
upstream_host = "lore.kernel.org/"

print(f"Subdirectories in '{directory}':")

file = open(filename, "ab")
# os.scandir() yields DirEntry objects
for entry in os.scandir(directory):
    # Check if the entry is a directory
    if not entry.is_dir():
        # ignore extra files in dir
        continue

    subdir = entry.name

    url = f"https://{upstream_host}{subdir}/_/text/config/raw"

    curl_command = [
        "curl",
        "-s",  # Silent mode
        "-L",  # Follow redirects
        url,  # The URL to request
    ]

    try:
        # subprocess.run() executes the command and waits for it to finish
        result = subprocess.run(
            curl_command,
            capture_output=True,  # Capture stdout and stderr
            text=False,  # Keep output as bytes (optional here, but ensures raw handling if we read it)
            check=True,  # Raise a CalledProcessError if curl returns a non-zero exit code (error)
        )

        # --- 3. Verification ---
        # Since curl handles the writing, we just verify the result
        if result.returncode != 0:
            raise ("Command failed", result)

        # You can also print any error output from curl
        if result.stderr:
            print("\nCurl Errors (if any):")
            print(result.stderr.decode("utf-8"))

        result_bytes = result.stdout
        if result_bytes and result_bytes.find(b"[publicinbox") > 0:
            print("Read data for", subdir)
            data = result.stdout.replace(
                b"/path/to/top-level-inbox", f"/data/{subdir}".encode()
            )
            data = data.replace(b"example.com", hostname.encode())
            data = data.replace(b"example.onion", hostname.encode())

            file.write(data)
            file.write(b"\n")
            file.flush()
            print("wrote data for", subdir)
        else:
            with open(filename + "_err", "ab") as err_file:
                err_file.write(b"err:")
                err_file.write(f"{subdir}".encode())
                err_file.write(result_bytes)
                err_file.write(b"\n")

    except subprocess.CalledProcessError as e:
        print(f"❌ Curl failed with return code {e.returncode}.")
        print("Error output:")
        print(e.stderr.decode("utf-8"))
        break
    except FileNotFoundError:
        print(
            "❌ Error: 'curl' command not found. Make sure curl is installed and accessible in your system's PATH."
        )
        break
    time.sleep(5)
file.close()
