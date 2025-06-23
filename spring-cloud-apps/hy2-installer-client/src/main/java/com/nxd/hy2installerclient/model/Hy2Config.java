package com.nxd.hy2installerclient.model;


import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.Map;

/**
 * Hysteria 2 配置文件的Java模型 (POJO).
 * 这个类的结构精确地映射了最终生成的 config.yaml 文件的结构。
 * Jackson库会使用这个类作为“蓝图”来生成YAML文件。
 * tls:
 * cert: your_cert.crt
 * key: your_key.key
 * <p>
 * auth:
 * type: password
 * password: Se7RAuFZ8Lzg
 * <p>
 * masquerade:
 * type: proxy
 * proxy:
 * url: https://news.ycombinator.com/
 * rewriteHost: true
 */
public class Hy2Config {
    public String listen;
    public TLS tls;
    public Auth auth;
    @JsonProperty("congestion_control")
    //拥塞控制
    public CongestionControl congestionControl;
    public Bandwidth bandwidth;
    //开启伪装
    public Masquerade masquerade;

    public static class TLS {
        public String cert;
        public String key;
    }

    public static class Auth {
        public String type = "password";
        public String password;
    }

    public static class CongestionControl {
        public String type = "bbr";//开启BBR
    }

    public static class Bandwidth {
        public String up;
        public String down;
    }

    public static class Masquerade {
        public String type = "proxy";
        public Map<String, Object> proxy = Map.of("url", "https://bing.com", "rewriteHost", true);
    }
}