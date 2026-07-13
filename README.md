<div align="center">

# 🏗️ Oracle WordPress Personal Infra

### Infraestrutura pessoal como código, rodando WordPress na Oracle Cloud com Terraform + Docker

*Um laboratório vivo de DevOps: provisionamento, hardening, backups e administração de servidores — tudo documentado e reproduzível.*

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.8.0-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://developer.hashicorp.com/terraform)
[![OCI](https://img.shields.io/badge/Oracle%20Cloud-Infrastructure-F80000?style=for-the-badge&logo=oracle&logoColor=white)](https://www.oracle.com/cloud/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![WordPress](https://img.shields.io/badge/WordPress-Personal%20Lab-21759B?style=for-the-badge&logo=wordpress&logoColor=white)](https://wordpress.org/)
[![Status](https://img.shields.io/badge/status-em%20desenvolvimento-yellow?style=for-the-badge)](#-roadmap)

</div>

---

## 📑 Sumário

| | | |
|---|---|---|
| [🧭 Sobre](#-sobre) | [🎯 Objetivos de estudo](#-objetivos-de-estudo) | [🗺️ Arquitetura atual](#️-arquitetura-atual) |
| [☁️ Recursos provisionados](#️-recursos-provisionados) | [📦 Stack WordPress](#-stack-wordpress) | [📂 Estrutura do repositório](#-estrutura-do-repositório) |
| [✅ Pré-requisitos](#-pré-requisitos) | [⚙️ Variáveis do Terraform](#️-variáveis-do-terraform) | [🔐 Credenciais e segurança](#-credenciais-e-segurança) |
| [🚀 Uso](#-uso) | [🔑 Acesso SSH](#-acesso-ssh) | [🛠️ Administração do WordPress](#️-administração-do-wordpress) |
| [💾 Persistência e backups](#-persistência-e-backups) | [🗓️ Roadmap](#️-roadmap) | [📏 Boas práticas](#-boas-práticas) |
| [📜 Histórico do projeto](#-histórico-do-projeto) | [👤 Autor](#-autor) | |

---

## 🧭 Sobre

Este repositório provisiona uma infraestrutura pessoal na **Oracle Cloud Infrastructure**, usando **Terraform**, para rodar uma stack WordPress completa em uma máquina virtual de baixo custo.

O projeto funciona como um laboratório prático para estudar:

`IaC` · `Oracle Cloud Infrastructure` · `administração Linux` · `Docker & Docker Compose` · `WordPress` · `Nginx (proxy reverso)` · `MariaDB` · `segurança & hardening` · `controle de acesso SSH` · `backups & restauração` · `HTTPS` · `monitoramento leve` · `automação & CI/CD`

> 💡 A infraestrutura foi inicialmente planejada para rodar o **BookCommerce** com K3s e Helm. Como a shape ARM desejada não estava disponível, o repositório virou um ambiente pessoal de estudos com WordPress — e o BookCommerce ganhará sua própria infra e state do Terraform, isolados desta VM.

---

## 🎯 Objetivos de estudo

Este não é um projeto de hospedagem comercial ou de alta disponibilidade. O foco é a prática hands-on:

1. Provisionamento completo de infraestrutura com Terraform
2. Bootstrap automático via cloud-init
3. Orquestração de containers com Docker Compose
4. Proxy reverso com Nginx
5. Persistência de banco de dados e arquivos
6. Restrição de SSH por IP
7. Domínio e HTTPS
8. Backups automatizados
9. Restauração de desastres
10. Hardening de SO e containers
11. Monitoramento de memória, disco e disponibilidade
12. Deploy automatizado com GitHub Actions
13. Migração do WordPress entre servidores
14. Testes de destruição/recriação da infra

---

## 🗺️ Arquitetura atual

```text
Internet
   │
   ├── SSH 22    → permitido apenas para IPs confiáveis
   ├── HTTP 80
   └── HTTPS 443 → reservado para configuração TLS futura

Oracle Cloud Infrastructure
   │
   ├── VCN
   │     └── Subnet pública
   ├── Internet Gateway
   ├── Route Table
   ├── Security List
   └── VM Ubuntu
         └── Docker Compose
               ├── Nginx
               ├── WordPress + Apache + PHP
               └── MariaDB
```

**Fluxo HTTP atual:**

```
Cliente → Nginx :80 → WordPress :80 → MariaDB :3306
```

> Somente o **Nginx** publica porta no host. WordPress e MariaDB ficam acessíveis apenas pela rede interna do Docker.

---

## ☁️ Recursos provisionados

O Terraform provisiona:

`VCN` · `Subnet pública` · `Internet Gateway` · `Route Table` · `Security List` · `Instância Compute` · `VNIC` · `IP público` · `Boot volume` · `Chave pública SSH` · `Metadata / cloud-init` · `Tags do projeto`

**Configuração atual da VM:**

| Recurso | Configuração |
|---|---|
| Shape | `VM.Standard.E2.1.Micro` |
| Arquitetura | x86-64 |
| Sistema operacional | Ubuntu 24.04 LTS |
| CPU apresentada | AMD EPYC |
| vCPUs | 2 |
| Memória | ~1 GB |
| Swap | 2 GB |
| Boot volume | 50 GB |
| Rede privada | Subnet pública da OCI |

> ⚠️ A shape deve permanecer dentro dos limites gratuitos ou contratados da conta — sempre confira os limites vigentes no Console da OCI.

---

## 📦 Stack WordPress

A aplicação roda inteiramente via Docker Compose.

### Containers

| Container | Imagem | Função |
|---|---|---|
| `wordpress-nginx` | `nginx:stable-alpine` | Proxy reverso / entrada HTTP |
| `wordpress-app` | `wordpress:php8.3-apache` | Aplicação WordPress |
| `wordpress-database` | `mariadb:11.4` | Banco de dados |

### Portas

| Serviço | Exposição |
|---|---|
| Nginx | `0.0.0.0:80 → 80` |
| WordPress | Apenas rede interna Docker |
| MariaDB | Apenas rede interna Docker |

### Limites de memória

A VM tem poucos recursos, então cada container tem teto definido:

| Serviço | Limite aproximado |
|---|---|
| MariaDB | 256m |
| WordPress | 448m |
| Nginx | 64m |

O MariaDB ainda recebe ajustes voltados a ambientes pequenos:

```ini
innodb-buffer-pool-size=64M
max-connections=15
performance-schema=OFF
```

---

## 📂 Estrutura do repositório

```
.
├── cloud-init/
│   ├── k3s.yaml.tftpl
│   └── wordpress.yaml.tftpl
├── docker/
│   └── wordpress-compose.yaml
├── scripts/
│   ├── bootstrap-wordpress.sh
│   └── .gitkeep
├── compute.tf
├── data.tf
├── locals.tf
├── network.tf
├── outputs.tf
├── providers.tf
├── security.tf
├── terraform.tfvars.example
├── variables.tf
├── versions.tf
├── .gitignore
├── .terraform.lock.hcl
└── README.md
```

**Responsabilidades:**

| Arquivo / diretório | Responsabilidade |
|---|---|
| `versions.tf` | Versões do Terraform e provider OCI |
| `providers.tf` | Configuração do provider OCI |
| `variables.tf` | Declaração e validação de variáveis |
| `locals.tf` | Prefixos, nomes e tags reutilizáveis |
| `data.tf` | Imagens, Availability Domains e Fault Domains |
| `network.tf` | VCN, subnet, gateway e rotas |
| `security.tf` | Regras de entrada e saída |
| `compute.tf` | Instância Compute, metadata e cloud-init |
| `outputs.tf` | IPs e identificadores úteis |
| `cloud-init/wordpress.yaml.tftpl` | Bootstrap inicial da VM WordPress |
| `scripts/bootstrap-wordpress.sh` | Instala Docker, cria swap e sobe a stack |
| `docker/wordpress-compose.yaml` | WordPress, MariaDB e Nginx |
| `cloud-init/k3s.yaml.tftpl` | Mantido para estudos futuros com K3s |

---

## ✅ Pré-requisitos

| Ferramenta | Versão / observação |
|---|---|
| Conta Oracle Cloud | Com acesso aos recursos utilizados |
| Terraform | `>= 1.8.0, < 2.0.0` |
| Provider OCI | Definido em `versions.tf` |
| Chave de API OCI | Configurada localmente |
| Chave SSH | Par de chaves para acesso à VM |
| Git | Para versionamento |

Definido em `versions.tf`:

```hcl
terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.21.0"
    }
  }
}
```

---

## ⚙️ Variáveis do Terraform

| Variável | Descrição |
|---|---|
| `region` | Região da Oracle Cloud |
| `compartment_ocid` | OCID do compartment |
| `project_name` | Prefixo dos recursos |
| `environment` | Ambiente da infraestrutura |
| `vcn_cidr_block` | CIDR da VCN |
| `public_subnet_cidr_block` | CIDR da subnet pública |
| `ssh_allowed_cidrs` | IPs autorizados para SSH |
| `web_allowed_cidr` | Rede autorizada para HTTP/HTTPS |
| `instance_shape` | Shape da VM |
| `instance_ocpus` | OCPUs (shapes Flex) |
| `instance_memory_in_gbs` | Memória (shapes Flex) |
| `boot_volume_size_in_gbs` | Tamanho do boot volume |
| `ssh_public_key_path` | Caminho da chave SSH pública |
| `fault_domain_index` | Fault Domain utilizado |

**Exemplo de `terraform.tfvars`:**

```hcl
region           = "sa-saopaulo-1"
compartment_ocid = "<COMPARTMENT_OCID>"

project_name = "wordpress-personal"
environment  = "prod"

vcn_cidr_block           = "10.0.0.0/16"
public_subnet_cidr_block = "10.0.1.0/24"

ssh_allowed_cidrs = [
  "<IP_PUBLICO_PRINCIPAL>/32",
  "<IP_PUBLICO_ALTERNATIVO>/32",
]

web_allowed_cidr = "0.0.0.0/0"

instance_shape = "VM.Standard.E2.1.Micro"

instance_ocpus         = 2
instance_memory_in_gbs = 12

boot_volume_size_in_gbs = 50

ssh_public_key_path = "/home/USUARIO/.ssh/oracle_wordpress.pub"
```

> As variáveis de CPU e memória só se aplicam a shapes que terminam com `.Flex`.

---

## 🔐 Credenciais e segurança

O provider OCI usa as credenciais locais já configuradas para acesso à API.

### 🚫 Nunca versionar

- Chave privada da API OCI
- Chave privada SSH
- `terraform.tfvars` real
- `terraform.tfstate` / `terraform.tfstate.backup`
- Arquivos `*.tfplan`
- Secrets do WordPress
- Senhas do banco
- Kubeconfig
- Arquivos de credenciais

O `terraform.tfvars.example` deve conter **apenas placeholders**.

### SSH com múltiplos IPs

```hcl
variable "ssh_allowed_cidrs" {
  description = "Conjunto de IPv4 públicos permitidos para acesso SSH."
  type        = set(string)
}
```

O `security.tf` cria uma regra para cada endereço:

```hcl
dynamic "ingress_security_rules" {
  for_each = var.ssh_allowed_cidrs
  iterator = ssh_cidr

  content {
    protocol    = "6"
    source      = ssh_cidr.value
    source_type = "CIDR_BLOCK"
    stateless   = false

    description = "Allow SSH from trusted administrator IP"

    tcp_options {
      min = 22
      max = 22
    }
  }
}
```

> ⚠️ A porta 22 **nunca** deve ser aberta para `0.0.0.0/0`.

Para descobrir seu IP público atual:

```bash
curl -4 https://api.ipify.org; echo
```

---

## 🚀 Uso

```bash
# Inicialização
terraform init

# Formatação
terraform fmt -recursive

# Validação
terraform validate

# Plano
terraform plan
terraform plan -out=wordpress.tfplan   # opcional: salvar o plano

# Aplicação
terraform apply
terraform apply "wordpress.tfplan"     # usando o plano salvo

# Destruição
terraform destroy
```

> 🛑 Antes de rodar `destroy`, sempre faça backup do banco e dos arquivos do WordPress.

### Proteção contra recriação acidental

Mudanças no script de bootstrap alteram o `user_data` da instância — e isso pode forçar a substituição da VM. Por isso o recurso usa:

```hcl
lifecycle {
  ignore_changes = [
    metadata["user_data"]
  ]
}
```

Com isso:

- o `user_data` atualizado é usado apenas na criação de **novas** VMs;
- a VM existente **não** é destruída só por mudança no script;
- mudanças de rede e segurança continuam sendo aplicadas normalmente.

Sempre revise o plano antes de aplicar. Um plano seguro para alterar apenas regras de segurança deve mostrar algo como:

```
Plan: 0 to add, 1 to change, 0 to destroy.
```

Se aparecer `must be replaced` ou `1 to destroy`, **pare e revise** antes de aplicar.

---

## 🔑 Acesso SSH

```bash
ssh -i ~/.ssh/oracle_wordpress ubuntu@<IP_PUBLICO>
```

Obtendo o IP via Terraform:

```bash
terraform output -raw instance_public_ip

# De qualquer diretório:
terraform \
  -chdir="$HOME/Documentos/Estudos/Java/Oracle-WordPress-Personal-Infra" \
  output -raw instance_public_ip
```

---

## 🛠️ Administração do WordPress

```bash
cd /opt/wordpress

# Containers
sudo docker compose ps

# Logs gerais
sudo docker compose logs --tail=100

# Logs por serviço
sudo docker compose logs --tail=100 wordpress
sudo docker compose logs --tail=100 database
sudo docker compose logs --tail=100 nginx

# Ciclo de vida
sudo docker compose restart
sudo docker compose down
sudo docker compose up -d

# Uso de recursos
sudo docker stats
```

---

## 💾 Persistência e backups

| Volume | Conteúdo |
|---|---|
| `database-data` | Dados do MariaDB |
| `wordpress-data` | Arquivos, plugins, temas e uploads |

Reiniciar containers ou a VM **não** apaga esses dados — mas eles ficam armazenados no disco da própria VM. Como o recurso usa `preserve_boot_volume = false`, **destruir a VM pode remover os dados permanentemente**.

Antes de qualquer destruição, faça backup de:

- Banco MariaDB
- Diretório do WordPress
- Arquivos de configuração
- Secrets necessários para restauração

> 🎯 Evolução planejada: armazenar backups no **OCI Object Storage**.

### 🐛 Problema corrigido: permissões dos secrets

Na primeira instalação, o WordPress não conseguia ler a senha do banco:

```
file_get_contents(/run/secrets/db_password): Permission denied
```

**Correção aplicada:**

```bash
chmod 0644 /opt/wordpress/secrets/db_password
chmod 0600 /opt/wordpress/secrets/db_root_password
```

Isso já foi incorporado ao `bootstrap-wordpress.sh`, então não requer mais intervenção manual.

### Comandos úteis do sistema

```bash
hostnamectl                             # info do sistema
free -h                                 # memória
df -h                                   # disco
uname -a                                # kernel
lscpu                                   # CPU
sudo cloud-init status --long           # status do cloud-init
sudo tail -n 200 /var/log/cloud-init-output.log   # logs do bootstrap
sudo apt update && sudo apt upgrade -y  # atualização do sistema
```

### HTTPS

Hoje o WordPress roda apenas por HTTP. A porta 443 já pode ser liberada pela infra, mas ainda falta:

- [ ] definir domínio / estratégia de DNS
- [ ] configurar certificado TLS
- [ ] montar certificados no container Nginx
- [ ] publicar a porta 443
- [ ] redirecionar HTTP → HTTPS
- [ ] configurar renovação automática
- [ ] validar headers de segurança

---

## 🗓️ Roadmap

<details>
<summary><b>Infraestrutura</b></summary>

- [x] Configurar provider OCI
- [x] Criar VCN
- [x] Criar subnet pública
- [x] Criar Internet Gateway
- [x] Criar Route Table
- [x] Criar Security List
- [x] Criar VM
- [x] Configurar chave SSH
- [x] Restringir SSH por IP
- [x] Permitir múltiplos IPs confiáveis
- [x] Criar swap
- [x] Instalar Docker automaticamente
- [x] Provisionar WordPress com cloud-init
- [x] Proteger a VM contra recriação por mudanças no `user_data`

</details>

<details>
<summary><b>WordPress</b></summary>

- [x] Executar WordPress em Docker
- [x] Executar MariaDB em container separado
- [x] Utilizar Nginx como proxy reverso
- [x] Criar volumes persistentes
- [x] Aplicar limites de memória
- [ ] Validar reinicialização automática após reboot
- [ ] Configurar domínio
- [ ] Configurar HTTPS
- [ ] Configurar SMTP
- [ ] Configurar cache leve
- [ ] Revisar plugins e temas instalados

</details>

<details>
<summary><b>Segurança</b></summary>

- [ ] Configurar headers de segurança no Nginx
- [ ] Proteger `wp-login.php`
- [ ] Limitar tentativas de login
- [ ] Avaliar Fail2ban
- [ ] Avaliar CrowdSec
- [ ] Revisar permissões dos arquivos
- [ ] Criar rotina de atualização segura
- [ ] Monitorar logs de acesso e autenticação
- [ ] Implementar alertas básicos

</details>

<details>
<summary><b>Backups</b></summary>

- [ ] Criar script de backup do MariaDB
- [ ] Criar backup dos arquivos do WordPress
- [ ] Armazenar backups no OCI Object Storage
- [ ] Criar política de retenção
- [ ] Automatizar com cron ou systemd timer
- [ ] Testar restauração completa
- [ ] Documentar recuperação de desastre

</details>

<details>
<summary><b>Automação</b></summary>

- [ ] Criar pipeline CI para validar Terraform
- [ ] Executar `terraform fmt -check`
- [ ] Executar `terraform validate`
- [ ] Criar análise de segurança do Terraform
- [ ] Criar deploy controlado da stack Docker
- [ ] Configurar atualização automatizada das imagens
- [ ] Criar monitoramento leve de disponibilidade

</details>

---

## 📏 Boas práticas

- ❌ Nunca versionar `terraform.tfvars`
- ❌ Nunca versionar chaves privadas
- ❌ Nunca versionar `terraform.tfstate`
- ❌ Nunca editar o state manualmente
- ❌ Nunca aplicar um plano sem revisar possíveis destruições
- ✅ Manter backup antes de alterações importantes
- ✅ Limitar o acesso SSH a IPs conhecidos
- ✅ Não expor diretamente WordPress ou MariaDB
- ✅ Usar senhas fortes e exclusivas
- ✅ Manter WordPress, temas e plugins atualizados
- ✅ Evitar plugins desnecessários
- ✅ Monitorar o uso de memória da VM
- ✅ Rodar `terraform fmt` e `terraform validate` antes de cada plano
- ✅ Manter o BookCommerce em infraestrutura e state separados

---

## 📜 Histórico do projeto

Este repositório começou como a infraestrutura planejada para o **BookCommerce**, usando uma VM ARM Ampere A1, K3s e Helm.

Diante da indisponibilidade de capacidade para essa shape, a infra foi adaptada para uma VM menor, rodando WordPress como laboratório pessoal. A infraestrutura futura do BookCommerce será mantida separadamente, evitando que mudanças de shape, cloud-init ou aplicação afetem este ambiente WordPress.

O arquivo `cloud-init/k3s.yaml.tftpl` permanece no projeto apenas como referência histórica e para estudos futuros — **não é usado** pela VM WordPress atual.

---

## 👤 Autor

Desenvolvido por **[@Sc4rlxrd](https://github.com/Sc4rlxrd)**

Projeto pessoal de estudos em: `Terraform` · `Oracle Cloud` · `Linux` · `Docker` · `WordPress` · `Segurança` · `Automação` · `Infraestrutura como Código`