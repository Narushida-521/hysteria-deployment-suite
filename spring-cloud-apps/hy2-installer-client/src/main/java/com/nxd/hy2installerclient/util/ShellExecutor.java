package com.nxd.hy2installerclient.util;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.file.Path;
import java.util.concurrent.TimeUnit;

/**
 * Shell命令执行器工具类。
 * 负责执行外部Linux命令并处理其输出。
 */
public class ShellExecutor {
    /**
     * 在默认目录下执行命令。
     *
     * @param command 要执行的命令及其参数，例如 "ls", "-l"
     * @throws Exception 如果命令执行失败
     */
    public static void execute(String... command) throws Exception {
        execute(command, null);
    }

    /**
     * 在指定的工作目录下执行命令。
     *
     * @param command    要执行的命令及其参数
     * @param workingDir 命令执行的工作目录
     * @throws Exception 如果命令执行失败
     */
    public static void execute(String[] command, Path workingDir) throws Exception {
        System.out.println("Executing command: " + String.join(" ", command));
        // 1. 创建一个ProcessBuilder对象，这是Java执行外部命令的标准方式
        ProcessBuilder pb = new ProcessBuilder(command);
        // 2. 如果指定了工作目录，就设置它
        if (workingDir != null) {
            pb.directory(workingDir.toFile());
        }
        // 3. 将错误输出流合并到标准输出流，这样我们就可以在一个地方读取所有输出信息
        pb.redirectErrorStream(true);
        // 4. 启动进程
        Process process = pb.start();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                System.out.println(line);
            }
        }
        // 5. 等待命令执行完毕，并获取退出码
        // 约定：退出码为0代表成功，非0代表失败
        boolean finished = process.waitFor(60, TimeUnit.SECONDS); // 最多等待60秒
        if (!finished) {
            process.destroyForcibly();
            throw new RuntimeException("命令执行超时: " + String.join(" ", command));
        }
        int exitCode = process.exitValue();
        if (exitCode != 0) {
            throw new RuntimeException("命令执行失败，退出码: " + exitCode + " 对于命令: " + String.join(" ", command));
        }
    }
}
