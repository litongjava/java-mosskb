package nexus.io.mosskb.config.boot;

import nexus.io.context.BootConfiguration;
import nexus.io.jfinal.aop.Aop;
import nexus.io.mosskb.service.kb.BackgroundImportService;
import nexus.io.mosskb.config.MossKbDbConfig;
import nexus.io.mosskb.config.MossKbEhCacheConfig;
import nexus.io.mosskb.config.MossKbEnjoyEngineConfig;
import nexus.io.mosskb.config.MossKbFastJsonConfig;
import nexus.io.mosskb.config.MossKbHandlerConfiguration;
import nexus.io.mosskb.config.MossKbInterceptorConfiguration;
import nexus.io.mosskb.config.MossKbPlaywrightConfig;
import nexus.io.mosskb.config.MossKbQuartzConfig;
import nexus.io.mosskb.config.MossKbTioServerConfig;
import nexus.io.mosskb.config.MossKbTokenStoreConfig;

public class MossKbBootConfig implements BootConfiguration {

  /**
   * 整套启动配置在一个 JVM 里只执行一次：其中的连接池、缓存、调度器和 t-io 服务器都不是可重复
   * 初始化的。生产启动只调用一次；测试里多个测试类会各自触发启动，靠这个标记保证幂等。
   */
  private static boolean configured;

  @Override
  public void config() throws Exception {
    if (configured) {
      return;
    }
    System.setProperty("net.sf.ehcache.skipUpdateCheck", "true");

    new MossKbDbConfig().config();
    new MossKbEhCacheConfig().config();
    new MossKbEnjoyEngineConfig().config();
    new MossKbFastJsonConfig().config();
    Aop.get(BackgroundImportService.class).recover();
    new MossKbHandlerConfiguration().config();
    new MossKbInterceptorConfiguration().config();
    new MossKbPlaywrightConfig().config();
    new MossKbQuartzConfig().config();
    new MossKbTioServerConfig().config();
    new MossKbTokenStoreConfig().config();
    configured = true;
  }
}
