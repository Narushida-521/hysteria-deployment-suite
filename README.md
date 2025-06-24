# **Hysteria 2 全能自动化部署套件**

欢迎使用 Hysteria 2 全能自动化部署套件。本项目是一个功能强大且高度灵活的解决方案，旨在满足从快速部署到企业级架构演示的各种复杂需求。无论您是希望一键启动服务的最终用户，还是需要研究微服务架构的开发者，都能在这里找到最适合您的部署模式。

## **快速导航**

* [项目概述](#bookmark=id.z0e51le2iwub)  
* [哪种部署模式适合我？](#bookmark=id.taqq4pq7llxn)  
* [🚀 **模式一：极速一键部署 (推荐)**](#bookmark=id.zie44ubkbk7h)  
* [🏢 **模式二：Spring Cloud企业级部署 (用于架构演示)**](#bookmark=id.4e9gg53kcxw)  
* [🐳 **模式三：Docker容器化部署 (推荐)**](#bookmark=id.tcoy32ar35)  
* [项目结构](#bookmark=id.8zt2jfqgwq2v)  
* [如何贡献](#bookmark=id.yt52ez5ke2su)  
* [许可证](#bookmark=id.6fwzqybm7jm9)

## **项目概述**

本套件创造性地将三种截然不同的部署哲学整合在一个统一的代码仓库中：

1. **纯Shell脚本**: 提供极致的便捷性，通过一条命令在任何Linux服务器上完成部署。  
2. **Spring Cloud架构**: 完整地演示了企业级应用中的分布式配置管理和微服务协作流程。  
3. **Docker容器**: 实现了环境的完全隔离和无可比拟的可移植性，是现代运维的最佳实践。

您可以根据您的具体需求和技术背景，自由选择最合适的部署模式。

## **哪种部署模式适合我？**

| 特性 | 模式一 (一键脚本) | 模式二 (Spring Cloud) | 模式三 (Docker) |
| :---- | :---- | :---- | :---- |
| **目标用户** | **普通用户, 快速部署者** | **开发者, 架构师** | **开发者, 运维工程师** |
| **易用性** | ⭐⭐⭐⭐⭐ (极简) | ⭐ (非常复杂) | ⭐⭐⭐⭐ (简单) |
| **灵活性** | ⭐⭐⭐ (中等) | ⭐⭐⭐⭐ (高) | ⭐⭐⭐⭐⭐ (极高) |
| **依赖环境** | Linux \+ Root权限 | Java 21, Maven, Git | Docker, Docker Compose |
| **核心优势** | 快速、无额外依赖 | 演示企业级架构、配置集中管理 | 环境隔离、跨平台、易迁移 |
| **适用场景** | 在新的VPS上快速搭建服务 | 满足特定技术栈要求、学习微服务 | 生产环境、标准化运维、本地开发 |

## **🚀 模式一：极速一键部署 (推荐)**

此模式适用于希望在任何一台新的Linux服务器上快速、无痛部署Hysteria 2的用户。您无需关心任何技术细节，只需一条命令即可。

#### **✅ 前提条件**

* 一台拥有 root 权限的Linux服务器 (Ubuntu, Debian, CentOS)。  
* 服务器可以正常访问 GitHub。

#### **🚀 开始部署**

请使用SSH登录到您的服务器，然后复制并执行以下单行命令：

bash \<(curl \-fsSL [https://raw.githubusercontent.com/Narushida-521/hysteria-deployment-suite/main/script/install.sh](https://raw.githubusercontent.com/Narushida-521/hysteria-deployment-suite/refs/heads/main/script/install.sh))

## **🏢 模式二：Spring Cloud企业级部署 (用于架构演示)**

**警告：此模式极其复杂，仅用于满足特定的企业级架构演示需求，不推荐普通用户使用。**

此模式完整地展示了如何利用Spring Cloud微服务（特别是分布式配置中心）来管理和执行一个自动化部署任务。

#### **✅ 前提条件**

* **本地开发环境:** 已安装 Java 21, Apache Maven 3.6+。  
* **配置仓库:** 您需要一个**私有的Git仓库**，用于存放hy2-installer.yml配置文件，并已配置好SSH密钥或PAT访问凭证。

#### **🛠️ 操作流程**

1. **克隆本项目**  
   git clone \[本GitHub仓库的SSH或HTTPS地址\]

2. **配置config-server**  
   * 进入 spring-cloud-apps/config-server/src/main/resources/application.yml。  
   * 修改 uri 为您自己的私有Git仓库地址。  
   * 填入您的SSH私钥或PAT凭证。  
3. **编译整个项目**  
   * 在项目根目录下，运行Maven命令来编译和打包所有Java应用：

​	mvn clean package

4. **准备并上传工具包**  
   * 创建一个新文件夹（例如toolkit）。  
   * 将 config-server/target/config-server-1.0.jar 和 hy2-installer-client/target/hy2-installer-client-1.0.jar 这两个文件复制到 toolkit 中。  
   * 将项目根目录下的 deploy.sh 总控脚本也复制到 toolkit 中。  
5. **在目标VPS上执行**  
   * 将整个 toolkit 文件夹上传到目标VPS。  
   * 登录VPS，进入 toolkit 文件夹，并运行总控脚本：

chmod \+x deploy.sh  
./deploy.sh

脚本将临时启动一个配置中心，并由部署客户端拉取配置后完成所有部署任务。

## **🐳 模式三：Docker容器化部署 (推荐)**

此模式利用Docker实现了环境的完全隔离和无可比拟的可移植性，是现代运维和持续集成/持续部署(CI/CD)的最佳实践。

检查服务器环境（首次部署需要）
检查 Docker 是否安装：
在服务器的命令行中输入 docker --version。如果能看到版本号，说明已安装。如果没有，请用以下一键脚本进行安装：
** bash curl -fsSL https://get.docker.com | bash
检查防火墙和安全组：
这是最容易被忽略但最关键的一步。请确保服务器的防火墙（如 ufw）和您云服务商（如阿里云、腾讯云、AWS）控制台里的“安全组”规则，已经为您计划使用的端口（比如 443）同时开放了 TCP 和 UDP 流量。
以 ufw 防火墙为例，开放 443 端口的命令是：
** sudo ufw allow 443/tcp
** sudo ufw allow 443/udp
** sudo ufw reload
第三步：执行“一键部署”命令
现在，请在您的服务器终端上，运行我们精心打造的、最终的单行部署命令。
请务必将 YOUR_DOCKERHUB_USERNAME 替换为您的真实用户名，并设置一个足够强的密码。
Bash
docker run -d --name stormgate --restart always --cap-add=NET_ADMIN -p 8443:443/udp -p 8443:443/tcp -v /root/stormgate_config:/etc/hysteria -e PASSWORD="20250624" -e MASQUERADE_URL="https://www.bing.com/" naxida/stormgate:1.0
## **项目结构**

hysteria-deployment-suite/  
├── docker/  
│   └── ... (Docker相关文件)  
├── script/  
│   └── install.sh  
├── spring-cloud-apps/  
│   ├── config-server/  
│   ├── hy2-installer-client/  
│   └── pom.xml (父POM)  
├── deploy.sh  
└── README.md

## **如何贡献**

欢迎对本项目进行贡献！您可以通过以下方式参与：

1. 提交Issues来报告Bug或提出功能建议。  
2. Fork本仓库，创建新的分支进行修改，然后提交Pull Request。

## **许可证**

本项目采用 [MIT许可证](https://opensource.org/licenses/MIT) 授权。
