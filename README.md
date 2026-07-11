# BookCommerce Oracle Infra

> Infraestrutura como código (Terraform) para provisionamento de recursos na Oracle Cloud Infrastructure e bootstrap de um cluster K3s para a plataforma BookCommerce.

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.8.0-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://developer.hashicorp.com/terraform)
[![OCI](https://img.shields.io/badge/Oracle%20Cloud-Free%20Tier-F80000?style=for-the-badge&logo=oracle&logoColor=white)](https://www.oracle.com/cloud/free/)
[![K3s](https://img.shields.io/badge/K3s-Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://k3s.io/)
[![Status](https://img.shields.io/badge/status-em%20desenvolvimento-yellow?style=for-the-badge)](#roadmap)

---

## Sumário

- [Sobre](#sobre)
- [Arquitetura planejada](#arquitetura-planejada)
- [Repositórios relacionados](#repositórios-relacionados)
- [Pré-requisitos](#pré-requisitos)
- [Estrutura de diretórios](#estrutura-de-diretórios)
- [Requisitos de versão](#requisitos-de-versão)
- [Variáveis do Terraform](#variáveis-do-terraform)
- [Credenciais e autenticação na OCI](#credenciais-e-autenticação-na-oci)
- [Uso](#uso)
- [Roadmap](#roadmap)
- [Boas práticas](#boas-práticas)
- [Autor](#autor)

---

## Sobre

Este repositório é a camada de **infraestrutura em nuvem** da plataforma [BookCommerce](https://github.com/Sc4rlxrd/BookCommerce): provisiona rede, instância(s) compute e o bootstrap do cluster **K3s** na camada **Always Free** da Oracle Cloud Infrastructure (OCI) usando **Terraform**.

O deploy da aplicação em si (charts, values, manifests Kubernetes) fica a cargo do repositório [BookCommerce-K8s-Helm](https://github.com/Sc4rlxrd/BookCommerce-K8s-Helm), que é instalado no cluster provisionado por este projeto.

> **Status atual:** projeto em desenvolvimento inicial. A versão do provider e as variáveis base já estão definidas em `versions.tf` e `variables.tf`; os recursos de rede, segurança, compute e o bootstrap do K3s ainda serão implementados. Veja o [Roadmap](#roadmap).

## Arquitetura planejada

```
Terraform
  ├─ Network (network.tf)      -> VCN e subnet pública
  ├─ Security (security.tf)    -> Security List / NSG
  ├─ Compute (compute.tf)      -> Instância(s) Ampere A1 (Always Free)
  │                                └─ cloud-init/ -> instalação do K3s
  └─ Outputs (outputs.tf)      -> IP público e dados de acesso

K3s (na instância provisionada)
  └─ kube-apiserver · kubelet · containerd

Helm (BookCommerce-K8s-Helm)
  ├─ gateway-service · identity-service · catalog-service
  ├─ order-service · payment-service · notification-service
  ├─ PostgreSQL · RabbitMQ · Redis
  └─ Prometheus · Grafana · Zipkin
```

`compute.tf`, `network.tf`, `security.tf`, `outputs.tf`, `providers.tf` e `cloud-init/` já existem no repositório, mas ainda estão vazios ou sem conteúdo versionado. Esta seção é atualizada conforme os recursos vão sendo implementados.

## Repositórios relacionados

| Repositório | Papel |
| --- | --- |
| **BookCommerce-Oracle-Infra** | Este repositório — infraestrutura na OCI e bootstrap do cluster K3s. |
| [BookCommerce-K8s-Helm](https://github.com/Sc4rlxrd/BookCommerce-K8s-Helm) | Umbrella chart Helm com todos os workloads da plataforma. |
| [BookCommerce](https://github.com/Sc4rlxrd/BookCommerce) | Repositório principal, com a visão geral da arquitetura event-driven e links para os microsserviços. |

## Pré-requisitos

| Ferramenta | Versão / Observação |
| --- | --- |
| Conta Oracle Cloud | Acesso ao **Always Free Tier** |
| [Terraform](https://developer.hashicorp.com/terraform/install) | `>= 1.8.0, < 2.0.0` |
| [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) | Configurado, ou credenciais de API geradas manualmente no console da OCI |
| OCID de Compartment | Válido na tenancy usada |
| `kubectl` / `helm` | Para interagir com o cluster remoto após o provisionamento (uso futuro) |

## Estrutura de diretórios

```
.
├── cloud-init/
├── scripts/
├── compute.tf
├── network.tf
├── outputs.tf
├── providers.tf
├── security.tf
├── terraform.tfvars.example
├── variables.tf
├── versions.tf
├── .gitignore
└── README.md
```

| Arquivo / diretório | Situação |
| --- | --- |
| `versions.tf` | Implementado — versão do Terraform e do provider `oci` |
| `variables.tf` | Implementado — variáveis base (`region`, `compartment_ocid`, `project_name`, `environment`) |
| `providers.tf` | Vazio — configuração do provider `oci` |
| `network.tf` | Vazio — VCN, subnet e rede |
| `security.tf` | Vazio — Security List / NSG |
| `compute.tf` | Vazio — instância(s) compute |
| `outputs.tf` | Vazio — outputs do módulo |
| `cloud-init/`, `scripts/` | Sem conteúdo versionado ainda |

> O `.gitignore` deve ignorar `*.tfvars` (exceto `.example`), `*.tfstate`, `*.tfstate.backup` e a pasta `.terraform/`, já que esses arquivos podem conter credenciais e estado sensível.

## Requisitos de versão

Definidos em `versions.tf`:

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

## Variáveis do Terraform

Definidas em `variables.tf`:

| Variável | Descrição | Tipo | Default | Validação |
| --- | --- | --- | --- | --- |
| `region` | Região da Oracle Cloud onde os recursos serão criados. | `string` | — | — |
| `compartment_ocid` | OCID do compartment que receberá os recursos (`sensitive`). | `string` | — | Deve começar com `ocid1.compartment.` |
| `project_name` | Prefixo usado no nome dos recursos. | `string` | `bookcommerce` | — |
| `environment` | Ambiente da infraestrutura. | `string` | `prod` | Deve ser `dev`, `staging` ou `prod` |

Novas variáveis (credenciais de API, chave SSH pública, shape/OCPU/memória da instância etc.) serão adicionadas conforme `network.tf`, `compute.tf` e `security.tf` forem implementados.

## Credenciais e autenticação na OCI

O provider `oci` autentica via credenciais de API da Oracle Cloud — chave privada, fingerprint e OCIDs de user e tenancy — configuradas em `providers.tf` (ainda vazio neste repositório).

**Nunca** versione a chave privada de API/SSH, nem um `terraform.tfvars` preenchido com valores reais.

Use `terraform.tfvars.example` como base para o seu `terraform.tfvars` local (ignorado pelo Git):

```hcl
region           = "<REGION>"
compartment_ocid = "<COMPARTMENT_OCID>"
project_name     = "bookcommerce"
environment      = "prod"
```

## Uso

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

Para desprovisionar:

```bash
terraform destroy -var-file="terraform.tfvars"
```

> Como `compute.tf`, `network.tf` e `security.tf` ainda estão vazios, `plan`/`apply` hoje não criam recursos na OCI — apenas validam a configuração base (`versions.tf` e `variables.tf`).

## Roadmap

- [ ] `providers.tf` — configuração do provider `oci` (autenticação via API key ou instance principal)
- [ ] `network.tf` — VCN, subnet pública e route table
- [ ] `security.tf` — Security List/NSG liberando as portas necessárias (SSH, HTTP/HTTPS, API do K3s)
- [ ] `compute.tf` — instância(s) Compute no shape Ampere A1 (Always Free)
- [ ] `cloud-init/` — script de bootstrap para instalação do K3s na criação da instância
- [ ] `outputs.tf` — IP público da instância e demais dados úteis para acesso
- [ ] Documentar acesso SSH, obtenção do kubeconfig e deploy do BookCommerce via Helm assim que o cluster estiver de pé

## Boas práticas

- Nunca versionar `terraform.tfvars`, chaves privadas de API/SSH ou arquivos `*.tfstate`.
- Manter o state do Terraform em backend remoto sempre que possível, mesmo em projetos pessoais.
- Rodar `terraform fmt -recursive` e `terraform validate` antes de todo `plan`/`apply`.
- Fixar versões de provider (`required_providers`) para evitar drift entre execuções, como já feito em `versions.tf`.
- Usar blocos `validation` nas variáveis críticas (como já feito em `compartment_ocid` e `environment`) para evitar erros silenciosos.
- Respeitar os limites do Always Free Tier (OCPUs, memória, block storage) ao definir o shape e os recursos da instância compute.

---

## Autor

Desenvolvido por [**@Sc4rlxrd**](https://github.com/Sc4rlxrd) — infraestrutura como código para a plataforma BookCommerce na Oracle Cloud.