
On Windows to install polytope you need a different approach. Try:

wsl -d Ubuntu -- curl -s https://polytope.com/install.sh | sh -s
This uses the Ubuntu WSL that was installed earlier. But first check if WSL/Ubuntu is ready:
wsl -d Ubuntu

then 
pt run stack --mcp to run it

use wsl terminal on windows and run these commands <br>
export PATH="$PATH:/root/.local/bin" <br>
cd /mnt/c/Users/achyu/OneDrive/Desktop/tele2project1-main <br>
pt run stack --mcp <br>
<img width="1920" height="1020" alt="image" src="https://github.com/user-attachments/assets/bcc7ac25-748a-4fb6-9052-1dfab14a54b2" />
<img width="1920" height="1020" alt="image" src="https://github.com/user-attachments/assets/09d734b7-79b6-4852-8db2-9a5a8c3eee73" />
