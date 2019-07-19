Steps to setup cert-manager in azure (AKS and azure dns zone):

# setup dns zone
1. register domain `xiaodong.world` in godaddy
2. create dns zone in azure with name `dev.xiaodong.world`
3. update godaddy to point ns endpoints in [azure dns zone]()

# install cert-manager in AKS
kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/00-crds.yaml
kubectl create namespace cert-manager
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install `
    --name cert-manager `
    --namespace cert-manager `
    --version v0.8.1 jetstack/cert-manager `
    --set ingressShim.defaultIssuerName=letsencrypt `
    --set ingressShim.defaultIssuerKind=ClusterIssuer `
    --set ingressShim.defaultACMEChallengeType=dns01 


# create cluster issuer 


# create wild card certificate 


# create ingress 


# error 

