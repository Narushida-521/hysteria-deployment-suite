package com.nxd.hy2installerclient.util;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream;

import java.io.BufferedInputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.concurrent.TimeUnit;

/**
 * 文件下载和解压工具类。
 * 使用OkHttp进行下载，使用Apache Commons Compress处理 .tar.gz 压缩包。
 */
public class Downloader {

    // 1. 创建一个OkHttpClient实例。
    // 它是线程安全的，我们可以在整个应用中复用这一个实例，性能更好。
    // 我们还为它设置了30秒的连接和读取超时，防止因网络问题卡死。
    private static final OkHttpClient client = new OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build();

    /**
     * 下载并解压 .tar.gz 文件，从中提取出指定的可执行文件。
     * @param executableName 我们要找的目标文件名，这里是 "hysteria"
     * @param url 文件的下载地址
     * @param installDir 我们要将文件安装到的目录
     * @throws Exception 如果下载或解压失败
     */
    public static void downloadAndExtract(String executableName, String url, Path installDir) throws Exception {
        System.out.println("[正在下载]" + executableName + " from " + url);

        // 2. 创建一个HTTP请求对象
        Request request = new Request.Builder().url(url).build();

        // 3. 执行请求并获取响应
        // try-with-resources 语句能确保网络连接和响应体在用完后被自动关闭
        try (Response response = client.newCall(request).execute()) {

            // 4. 检查HTTP响应码，如果不是200 OK，就说明下载失败
            if (!response.isSuccessful()) {
                throw new RuntimeException("下载失败，HTTP响应码: " + response.code() + " " + response.message());
            }

            ResponseBody body = response.body();
            if (body == null) {
                throw new RuntimeException("下载响应体为空");
            }
            // 5. 解压 .tar.gz 流
            // 这是一个“套娃”式的过程，像剥洋葱
            try (InputStream bodyStream = body.byteStream();
                 // 第一层：用BufferedInputStream增加读取效率
                 BufferedInputStream bufferedIn = new BufferedInputStream(bodyStream);
                 // 第二层：用GzipCompressorInputStream解开 .gz 压缩
                 GzipCompressorInputStream gzipIn = new GzipCompressorInputStream(bufferedIn);
                 // 第三层：用TarArchiveInputStream解开 .tar 归档
                 TarArchiveInputStream tarIn = new TarArchiveInputStream(gzipIn)) {
                TarArchiveEntry entry;
                // 6. 遍历tar包里的每一个文件/目录
                while ((entry = tarIn.getNextTarEntry()) != null) {
                    // 7. 判断是否是我们想要的文件
                    // 我们只关心文件，不关心目录，并且文件名必须是我们想找的那个
                    if (!entry.isDirectory() && entry.getName().endsWith(executableName)) {
                        // 找到了！
                        Path destPath = installDir.resolve(executableName);
                        // 8. 将文件内容从压缩流中复制到我们本地的目标路径
                        Files.copy(tarIn, destPath, StandardCopyOption.REPLACE_EXISTING);
                        System.out.println("[EXTRACT]" + entry.getName() + " -> " + destPath);
                        // 9. 任务完成，直接退出方法
                        return;
                    }
                }
            }
        }
        // 如果整个循环都跑完了还没找到，就说明压缩包里没有我们需要的文件
        throw new RuntimeException("在压缩包 " + url + " 中未找到 '" + executableName + "' 可执行文件");
    }
}