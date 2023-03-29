Kind = "ingress-gateway"
Name = "ingress-gateway"
Listeners = [
  {
    Port = 9090
    Protocol = "tcp"
    Services = [
      {
        Name = "vault-go-demo"
      }
    ]
  },
  {
    Port = 8080
    Protocol = "http"
    Services = [
      {
        Name = "go-movies-app"
      }
    ]
  }
]