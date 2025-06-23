package com.nxd.hy2installerclient.util;

import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Hysteria 2 后台启动脚本生成器。
 */
public class ScriptGenerator {

    /**
     * 创建一个用于在后台启动Hysteria 2的Shell脚本。
     * @param installDir Hysteria 2的安装目录
     * @return 生成的脚本文件的路径
     * @throws Exception 如果文件写入失败
     */
    public static Path createHy2StartupScript(Path installDir) throws Exception {

        // 1. 使用Java 11+ 的文本块(Text Blocks)功能，可以非常方便地定义多行字符串。
        // 整个脚本的内容被清晰地定义在这里。
        String scriptContent = """
                #!/bin/bash

                # 首先，切换到Hysteria 2的安装目录，确保后续命令在正确的上下文中执行
                cd %s

                # 使用nohup和&让程序在后台持久运行
                # nohup: 保证在用户退出SSH会话后，程序不会被系统杀死
                # > hy2.log: 将所有标准输出重定向到hy2.log文件
                # 2>&1: 将所有错误输出也重定向到标准输出，最终都进入hy2.log
                # &: 让命令在后台执行，立即返回终端控制权
                nohup ./hysteria server -c config.yaml > hy2.log 2>&1 &

                # 将后台进程的ID（PID）写入hy2pid.log文件
                # $! 是一个Shell特殊变量，代表最后一个在后台运行的进程的PID
                # 这非常有用，方便我们以后管理这个进程（比如停止或重启）
                echo $! > hy2pid.log
                """;

        // 2. 使用String.format()方法，将脚本中的占位符(%s)替换成实际的安装目录路径
        String finalScriptContent = String.format(scriptContent, installDir.toAbsolutePath());

        // 3. 定义脚本文件的最终路径
        Path scriptPath = installDir.resolve("start.sh");

        // 4. 使用Java NIO的Files.writeString()方法，将脚本内容写入文件
        Files.writeString(scriptPath, finalScriptContent);

        System.out.println("  [SCRIPT] 启动脚本已生成在: " + scriptPath);

        // 5. 返回生成的脚本路径，方便后续的步骤（比如给它添加执行权限）使用
        return scriptPath;
    }
}