/// Списки маршрутизации, общие для всех ядер.
abstract final class RoutingDefaults {
  /// Сервисы РФ в нотации xray: `domain:` — домен с поддоменами, `full:` — точный домен.
  static const List<String> ruServicesDomains = [
    'domain:2gis.ru', 'domain:2gis.com', 'domain:ads.x5.ru', 'domain:aif.ru',
    'domain:aeroflot.ru', 'domain:alfabank.ru', 'domain:api.oneme.ru', 'domain:avito.ru',
    'domain:beeline.ru', 'domain:burgerkingrus.ru', 'domain:dellin.ru', 'domain:drive2.ru',
    'domain:dzen.ru', 'domain:fd.oneme.ru', 'domain:flypobeda.ru', 'domain:forbes.ru',
    'domain:gazeta.ru', 'domain:gazprombank.ru', 'domain:gismeteo.ru', 'domain:gosuslugi.ru',
    'domain:hh.ru', 'domain:i.oneme.ru', 'domain:kontur.ru', 'domain:kontur.host',
    'domain:kp.ru', 'domain:kuper.ru', 'domain:lenta.ru', 'domain:mail.ru', 'domain:max.ru',
    'domain:megamarket.ru', 'domain:megamarket.tech', 'domain:megafon.ru',
    'domain:miniapps.max.ru', 'domain:moex.com', 'domain:motivtelecom.ru', 'domain:ozon.ru',
    'domain:pervye.ru', 'domain:psbank.ru', 'domain:rambler.ru', 'domain:rambler-co.ru',
    'domain:rbc.ru', 'domain:reg.ru', 'domain:reviews.2gis.com', 'domain:rg.ru',
    'domain:ria.ru', 'domain:rustore.ru', 'domain:rutube.ru', 'domain:ruwiki.ru',
    'domain:rzd.ru', 'domain:sdk-api.apptracer.ru', 'domain:sirena-travel.ru',
    'domain:sravni.ru', 'domain:st.max.ru', 'domain:t-j.ru', 'domain:t2.ru',
    'domain:tank-online.com', 'domain:taximaxim.ru', 'domain:tbank-online.com',
    'domain:tildaapi.com', 'domain:tns-counter.ru', 'domain:tracker-api.vk-analytics.ru',
    'domain:trvl.yandex.net', 'domain:tutu.ru', 'domain:vk.com', 'domain:vk.ru',
    'domain:vkvideo.ru', 'domain:vtb.ru', 'domain:x5.ru',
    'domain:xn--90acagbhgpca7c8c7f.xn--p1ai', 'domain:xn--80ajghhoc2aj1c8b.xn--p1ai',
    'domain:xn--90aivcdt6dxbc.xn--p1ai', 'domain:xn--b1aew.xn--p1ai',
    'domain:ya.ru', 'domain:yandex.ru', 'domain:yandex.net', 'domain:yandex.com',
    'domain:yandexcloud.net', 'domain:yastatic.net',
    'full:go.yandex', 'full:ru.ruwiki.ru',
  ];
}
