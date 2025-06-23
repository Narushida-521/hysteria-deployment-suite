package com.nxd.hy2installerclient.util;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.fasterxml.jackson.dataformat.yaml.YAMLGenerator;
import com.nxd.hy2installerclient.model.Hy2Config;

import java.nio.file.Path;

/**
 * Hysteria 2 的 config.yaml 配置文件生成器。
 * 使用Jackson库和Hy2Config模型类来确保生成的YAML文件结构正确、格式优美。
 */
public class ConfigGenerator {

    /**
     * 创建Hysteria 2的配置文件。
     *
     * @param installDir Hysteria 2的安装目录
     * @param port       监听端口
     * @param password   连接密码
     * @param fakeDomain 用于TLS证书的伪装域名 (SNI)
     * @param up         上行带宽
     * @param down       下行带宽
     * @throws Exception 如果文件写入失败
     */
    public static void createHy2Config(Path installDir, int port, String password, String fakeDomain, String up, String down) throws Exception {
        // 1. 创建我们的“蓝图”实例
        Hy2Config config = new Hy2Config();
        // 2. 将从配置中心获取的参数，填充到“蓝图”的对应位置
        config.listen = ":" + port;
        // 填充TLS配置，指向我们即将生成的证书和密钥文件
        config.tls = new Hy2Config.TLS();
        config.tls.cert = installDir.resolve("server.crt").toAbsolutePath().toString();
        config.tls.key = installDir.resolve("server.key").toAbsolutePath().toString();
        // 填充认证信息
        config.auth = new Hy2Config.Auth();
        config.auth.password = password;
        // 填充拥塞控制，默认使用我们模型类中定义的"bbr"
        config.congestionControl = new Hy2Config.CongestionControl();
        // 填充带宽信息
        config.bandwidth = new Hy2Config.Bandwidth();
        config.bandwidth.up = up;
        config.bandwidth.down = down;
        // 填充流量伪装
        config.masquerade = new Hy2Config.Masquerade();
        // 伪装的具体URL已经在模型类中硬编码为bing.com，这里无需再次设置
        // 3. 创建一个为YAML定制的Jackson“打印机” (ObjectMapper)
        // 我们通过YAMLFactory来告诉Jackson我们要输出的是YAML格式，而不是默认的JSON
        // disable(WRITE_DOC_START_MARKER) 是一个优化，它会阻止Jackson在文件开头写入"---"分隔符，让文件更纯净
        ObjectMapper mapper = new ObjectMapper(new YAMLFactory().disable(YAMLGenerator.Feature.WRITE_DOC_START_MARKER));
        // 4. 指定最终文件的生成路径
        Path configPath = installDir.resolve("config.yaml");
        // 5. 执行“打印”操作：将Java对象(config)写入到目标文件(configPath)
        // writerWithDefaultPrettyPrinter() 会让输出的YAML格式自动对齐、带缩进，非常美观
        mapper.writerWithDefaultPrettyPrinter().writeValue(configPath.toFile(), config);
        System.out.println("config.yaml 已生成在: " + configPath);
    }
}