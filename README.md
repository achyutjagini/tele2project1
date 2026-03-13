install polytope
curl -s https://polytope.com/install.sh | sh -s

On Windows, you need a different approach. Try:

wsl -d Ubuntu -- curl -s https://polytope.com/install.sh | sh -s
This uses the Ubuntu WSL that was installed earlier. But first check if WSL/Ubuntu is ready:
wsl -d Ubuntu

then 
pt run stack --mcp to run it
