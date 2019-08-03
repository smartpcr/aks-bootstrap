sudo apt install default-jre
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"

sudo sudo apt-get install -y build-essential make cmake scons curl git \
    ruby autoconf automake autoconf-archive \
    gettext libtool flex bison \
    libbz2-dev libcurl4-openssl-dev \
    libexpat-dev libncurses-dev

echo "Installing linuxbrew"
if [ -f "/usr/bin/brew" ]; then
    echo "brew already installed"
else
    cd ~/
    git clone https://github.com/Homebrew/linuxbrew.git ~/.linuxbrew
    echo "export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig:$PKG_CONFIG_PATH" > ~/.zshrc
    ## Setup linux brew
    echo "export LINUXBREWHOME=$HOME/.linuxbrew" > ~/.zshrc
    echo "export PATH=$LINUXBREWHOME/bin:$PATH" > ~/.zshrc
    echo "export MANPATH=$LINUXBREWHOME/man:$MANPATH" > ~/.zshrc
    echo "export PKG_CONFIG_PATH=$LINUXBREWHOME/lib64/pkgconfig:$LINUXBREWHOME/lib/pkgconfig:$PKG_CONFIG_PATH" > ~/.zshrc
    echo "export LD_LIBRARY_PATH=$LINUXBREWHOME/lib64:$LINUXBREWHOME/lib:$LD_LIBRARY_PATH" > ~/.zshrc
    brew update
    brew install git
fi


echo "install snap and unzip"
sudo apt update
if [ -f "/usr/bin/snap" ]; then
    echo "snap already installed"
else
    sudo apt install snapd
    sudo apt-get install unzip
fi

echo "install openssl"
if [ -f "/usr/bin/openssl" ]; then
    echo "openssl already installed"
else
    brew install openssl
fi


echo "install jq"
if [ -f "/usr/local/bin/jq" ]; then
    echo "jq already installed"
else
    brew install jq
fi


echo "install acme.sh"
if [ -f "~/.acme.sh/acme.sh" ]; then
    echo "acme.sh already installed"
else
    curl https://get.acme.sh | sh
fi

# echo "setup git credential manager"
# git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/libexec/git-core/git-credential-manager.exe"


echo "Install google chrome"
if [ -f "/usr/bin/google-chrome" ]; then
    echo "chrome already installed"
else
    sudo apt-get install xdg-utils
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo dpkg -i google-chrome-stable_current_amd64.deb
    rm ./google-chrome-stable_current_amd64.deb
fi


echo "installing kubectl..."
if [ -f "/usr/local/bin/kubectl" ]; then
    echo "kubectl already installed"
else
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
    chmod +x kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
fi


echo "installing helm..."
if [ -f "/usr/local/bin/helm" ]; then
    echo "helm already installed"
    # note: DO NOT use vscode extension `vscode-helm`
    # it introduces an env variable: TILLER_NAMESPACE,
    # that's been causing problem after switched to different cluster
else
    curl -LO https://get.helm.sh/helm-v2.14.3-linux-amd64.tar.gz
    tar -zxvf helm-v2.14.3-linux-amd64.tar.gz
    chmod +x ./linux-amd64/helm
    sudo mv ./linux-amd64/helm /usr/local/bin/helm
    rm helm-v2.14.3-linux-amd64.tar.gz
    rm -rf linux-amd64
fi


echo "installing fabrikate..."
if [ -f "/usr/local/bin/fab" ]; then
    echo "fab already installed"
else
    curl -LO 'https://github.com/microsoft/fabrikate/releases/download/0.15.1/fab-v0.15.1-linux-amd64.zip'
    unzip fab-v0.15.1-linux-amd64.zip
    rm fab-v0.15.1-linux-amd64.zip
    chmod +x fab
    sudo mv ./fab /usr/local/bin/fab
fi


echo "Installing terraform"
if [ -f "/usr/local/bin/terraform" ]; then
    echo "Terraform already installed"
else

    wget https://releases.hashicorp.com/terraform/0.12.6/terraform_0.12.6_linux_amd64.zip
    unzip terraform_0.12.6_linux_amd64.zip
    sudo chmod +x terraform
    sudo mv terraform /usr/local/bin/
    rm terraform_0.12.6_linux_amd64.zip
fi


echo "install kustomize"
if [ -f "/usr/local/bin/kustomize" ] then
    echo "kustomize already installed"
else
    brew install kustomize
fi


echo "Install fluxctl"
if [ -f "/usr/binfluxctl" ]; then
    echo "fluxctl already installed"
else
    sudo brew install fluxctl
fi


echo "update package repo"
sudo apt-get install -y gpg
wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo dpkg --purge packages-microsoft-prod && sudo dpkg -i packages-microsoft-prod.deb
sudo add-apt-repository universe
sudo apt-get update


echo "installing powershell"
if [ -f "/usr/bin/pwsh" ]; then
    echo "pwsh already installed"
else
    sudo apt-get install -y powershell
fi


echo "install .net core"
if [ -f "/usr/bin/dotnet" ]; then
    echo ".net core already installed"
else
    sudo apt-get install dotnet-sdk-2.2
fi


echo "install az-cli"
if [ -f "/usr/bin/az" ]; then
    echo "AZ-cli already installed"
else
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi


echo "remove keys"
rm packages-microsoft-prod.deb


echo "install pulumi"
if [ -f "/usr/local/bin/pulumi" ]; then
    echo "pulumi already installed"
else
    brew install pulumi
fi