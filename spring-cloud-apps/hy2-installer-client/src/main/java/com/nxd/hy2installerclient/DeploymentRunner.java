package com.nxd.hy2installerclient;

import com.nxd.hy2installerclient.util.ConfigGenerator;
import com.nxd.hy2installerclient.util.Downloader;
import com.nxd.hy2installerclient.util.ScriptGenerator;
import com.nxd.hy2installerclient.util.ShellExecutor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@Component
public class DeploymentRunner implements CommandLineRunner {
    @Value("${hysteria.deployment.port}")
    private int port;
    @Value("${hysteria.deployment.password}")
    private String password;
    @Value("${hysteria.deployment.fake-domain}")
    private String fakeDomain;
    @Value("${hysteria.deployment.bandwidth-up}")
    private String bandwidthUp;
    @Value("${hysteria.deployment.bandwidth-down}")
    private String bandwidthDown;

    private static final Path INSTALL_DIR = Paths.get(System.getProperty("user.home"), ".autohy2");
    private static final String HY2_VERSION = "2.6.2";

    @Override
    public void run(String... args) throws Exception {
        System.out.println("--- 成功连接配置中心，获取到部署配置 ---");
        System.out.println("  端口: " + port);
        System.out.println("  密码: " + password.replaceAll(".", "*"));
        System.out.println("  伪装域名(SNI): " + fakeDomain);
        System.out.println("----------------------------------------");

        System.out.println("1/7: 创建安装目录: " + INSTALL_DIR);
        Files.createDirectories(INSTALL_DIR);

        System.out.println("2/7: 尝试开启内核BBR优化...");
        enableKernelBbr();

        System.out.println("3/7: 下载并解压 Hysteria 2...");
        String osArch = System.getProperty("os.arch").contains("aarch64") ? "arm64" : "amd64";
        String hy2Url = "https://github.com/apernet/hysteria/releases/download/v%s/hysteria-linux-%s.tar.gz".formatted(HY2_VERSION, osArch);
        Downloader.downloadAndExtract("hysteria", hy2Url, INSTALL_DIR);
        ShellExecutor.execute("chmod", "+x", INSTALL_DIR.resolve("hysteria").toAbsolutePath().toString());

        System.out.println("4/7: 生成自签名证书...");
        String opensslCommand = "openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout %s -out %s -subj /CN=%s -days 3650".formatted(
                INSTALL_DIR.resolve("server.key"), INSTALL_DIR.resolve("server.crt"), fakeDomain
        );
        ShellExecutor.execute(new String[]{"/bin/sh", "-c", opensslCommand}, INSTALL_DIR);

        System.out.println("5/7: 生成 Hysteria 2 配置文件...");
        ConfigGenerator.createHy2Config(INSTALL_DIR, port, password, fakeDomain, bandwidthUp, bandwidthDown);

        System.out.println("6/7: 启动Hysteria 2服务...");
        try {
            ShellExecutor.execute("/bin/sh", "-c", "pkill -f 'hysteria server' || true");
            Thread.sleep(1000);
        } catch (Exception e) {
            System.out.println("  [INFO] 清理旧进程时发生警告，可能是因为没有旧进程在运行，可以忽略。");
        }
        Path startScript = ScriptGenerator.createHy2StartupScript(INSTALL_DIR);
        ShellExecutor.execute("chmod", "+x", startScript.toAbsolutePath().toString());
        ShellExecutor.execute(startScript.toAbsolutePath().toString());

        System.out.println("7/7: 配置防火墙...");
        enableFirewall();

        System.out.println("\n🎉🎉🎉 Hysteria 2 部署任务执行完毕! 🎉🎉🎉");
        System.out.println("您可以通过 `tail -f " + INSTALL_DIR.resolve("hy2.log") + "` 命令查看 Hysteria 2 实时日志。");

        printClientConfiguration();
    }

    private void printClientConfiguration() {
        System.out.println("\n========================================================================");
        System.out.println("✅ Hysteria 2 节点配置信息 (请复制到您的客户端中使用)");
        System.out.println("------------------------------------------------------------------------");
        System.out.println("   地址 (Address):      [您的VPS公网IP]  <-- 请手动替换成您的服务器IP");
        System.out.println("   端口 (Port):         " + port);
        System.out.println("   密码 (Auth):         " + password);
        System.out.println("   服务器名称/SNI:       " + fakeDomain);
        System.out.println("   跳过证书验证 (insecure): true");
        System.out.println("   上传带宽 (UP):       " + bandwidthUp);
        System.out.println("   下载带宽 (DOWN):     " + bandwidthDown);
        System.out.println("------------------------------------------------------------------------");
        System.out.println("提示: 因为我们使用的是自签名证书，请务必在客户端开启“允许不安全连接”或“跳过证书验证”选项。");
        System.out.println("========================================================================");
    }

    private void enableKernelBbr() {
        try {
            String bbrConfig = "\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n";
            String command = "echo '" + bbrConfig + "' | sudo tee -a /etc/sysctl.conf";
            ShellExecutor.execute("/bin/sh", "-c", command);
            ShellExecutor.execute("sudo", "sysctl", "-p");
            System.out.println("  ✅ 内核BBR配置已应用。");
        } catch (Exception e) {
            System.err.println("  ⚠️ 开启内核BBR时发生警告(可能是权限不足或内核不支持): " + e.getMessage());
        }
    }

    private void enableFirewall() {
        try {
            ShellExecutor.execute("sudo", "ufw", "status");
            ShellExecutor.execute("sudo", "ufw", "allow", String.valueOf(port) + "/udp");
            System.out.println("  ✅ 防火墙已放行端口: " + port + "/udp");
        } catch (Exception e) {
            System.err.println("  ⚠️ 配置防火墙时发生警告(可能是ufw未安装或未启用): " + e.getMessage());
        }
    }
}