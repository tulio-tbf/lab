# Orientação de escolha da engine

**Para o Lab, comece com Docker** se sua equipe usa macOS, Windows ou WSL, ou
se seu fluxo depende de projetos Compose complexos, Dev Containers e
Testcontainers. **Considere Podman** em Linux nativo se você prioriza
containers rootless, uma CLI sem daemon central ou um fluxo com pods e
manifestos Kubernetes. O Podman é o alvo do MVP em Linux rootless e a
validação integrada do Lab ainda está pendente. [Guia do Docker](GUIA-DOCKER.md) · [Guia do Podman](GUIA-PODMAN.md)

| Critério | Podman | Docker |
| --- | --- | --- |
| **Arquitetura** | A CLI pode operar sem daemon central. O Lab usa rootless e ativa o socket da API para o Traefik. | O Docker Engine usa o daemon `dockerd`, normalmente como root em instalações convencionais. Há modo rootless. [Docker rootless](https://docs.docker.com/engine/security/rootless/) |
| **Licenciamento** | Podman e Podman Desktop usam Apache 2.0, com uso comercial permitido nos termos da licença. [Projeto Podman](https://podman.io/) | Docker Engine é open source. Docker Desktop tem condições próprias de gratuidade e assinatura. [Docker Engine](https://docs.docker.com/engine/install/#licensing) · [Docker Desktop](https://docs.docker.com/subscription-billing/desktop-license/) |
| **Linux** | Nativo. Rootless usa mapeamento de usuários e pode exigir ajustes em permissões, portas e SELinux. | Nativo com Docker Engine. É o caminho padrão do Lab. |
| **macOS e Windows** | Para containers Linux, usa uma VM ou o backend WSL. A integração com o Lab está fora do escopo do MVP. | Docker Desktop é o caminho documentado para macOS e Windows. O Docker Engine também pode rodar no WSL. |
| **Compose** | `podman compose` delega a um provider externo. O Lab usa `podman-compose`. [Documentação do comando](https://docs.podman.io/en/stable/markdown/podman-compose.1.html) | `docker compose` é a implementação de referência para os arquivos gerados pelo Lab. |
| **Kubernetes** | Executa pods localmente e pode gerar YAML com `podman kube generate`. [Referência do comando](https://docs.podman.io/en/latest/markdown/podman-kube-generate.1.html) | Docker Desktop oferece um cluster Kubernetes local integrado. [Kubernetes no Docker Desktop](https://docs.docker.com/desktop/use-desktop/kubernetes/) |

## Quando considerar Podman

- **Custo em equipes que usam Desktop.** A licença do Podman Desktop evita uma
  assinatura obrigatória do produto. Para o Docker Desktop, a documentação
  prevê gratuidade para uso pessoal, educação, projetos open source não
  comerciais e pequenas empresas com menos de 250 funcionários **e** receita
  anual inferior a US$ 10 milhões. O uso profissional fora da faixa gratuita
  e o uso por entidades governamentais exigem assinatura. Em Linux, considere
  também o Docker Engine instalado separadamente. [Termos do Docker Desktop](https://docs.docker.com/subscription-billing/desktop-license/)
- **Privilégios no host Linux.** Rootless executa os containers com os
  privilégios do usuário que iniciou a engine. O root do container costuma
  mapear para esse usuário no host. Aplicações com outros UIDs podem gerar
  arquivos sob IDs subordinados e exigir ajustes nos bind mounts.
  [Mapeamento de usuários no Podman](https://docs.podman.io/en/stable/markdown/podman-create.1.html)
- **Memória em repouso.** Sem um daemon central permanente, o Podman pode
  reduzir o consumo de base. Se RAM for o critério decisivo, compare no mesmo
  host com os mesmos serviços, incluindo o proxy, a API e os processos
  auxiliares. [Arquitetura do Podman](https://podman.io/)
- **Fluxo com Kubernetes.** Gere um manifesto inicial de containers ou pods
  com `podman kube generate` e revise rede, armazenamento e segurança para
  o cluster de destino. Comandos como `podman run`, `podman build` e
  `podman ps` são familiares para quem usa a CLI do Docker.
  [Geração de manifestos](https://docs.podman.io/en/latest/markdown/podman-kube-generate.1.html)

## Quando preferir Docker

- **Integração com ferramentas.** Se sua equipe já usa Dev Containers e
  Testcontainers com Docker, mantenha o fluxo conhecido. Com Podman, o VS Code
  pode exigir `dev.containers.dockerPath` e o Testcontainers para Java pode
  exigir `DOCKER_HOST` e ajustes dependentes do ambiente.
  [VS Code Dev Containers](https://code.visualstudio.com/remote/advancedcontainers/docker-options) · [Testcontainers para Java](https://java.testcontainers.org/supported_docker_environment/)
- **Projetos Compose legados ou complexos.** Redes, volumes e opções de build
  específicos merecem teste com o provider antes da adoção. O Lab usa o
  socket compatível com Docker para o Traefik em Podman. A descoberta
  dinâmica de rotas ainda precisa ser confirmada em Linux nativo.
  [Provider Compose do Podman](https://docs.podman.io/en/stable/markdown/podman-compose.1.html)
- **Portas e diagnóstico.** Se o ambiente depende da porta 80, confira a
  política do host antes de adotar Podman rootless. O Lab usa a porta 8000 com
  Podman por padrão. O guia Docker também cobre mais procedimentos por
  serviço. [Guia do Docker](GUIA-DOCKER.md) · [Guia do Podman](GUIA-PODMAN.md)
