package com.litongjava.mosskb.regression;

import nexus.io.mosskb.config.MossKbDbConfig;
import nexus.io.tio.utils.environment.EnvUtils;

/**
 * 回归测试共用的数据库引导。
 *
 * <p>
 * MossKbDbConfig 会把 ActiveRecord 配置注册成全局唯一的名字，同一个 JVM 里初始化两次会抛
 * IllegalArgumentException。这里只初始化一次；pom 里同时把 surefire 配成每个测试类单独 fork，
 * 避免和其它测试类互相影响。
 */
final class RegressionDb {

  private static boolean initialized;

  private RegressionDb() {
  }

  static synchronized void init() {
    if (initialized) {
      return;
    }
    EnvUtils.load();
    new MossKbDbConfig().config();
    initialized = true;
  }
}
