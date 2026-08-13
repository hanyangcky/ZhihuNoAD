//
//  ZHNASettingsPanel.h
//  摇一摇呼出的设置面板
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void ZHNAInstallSettingsPanel(void);

/// 在任何时机呼出主设置面板（摇一摇与"知乎设置页内一行"都会调它）。
/// 内部通过 runtime 取 keyWindow，不引入 UIKit 链接依赖。
void ZHNAOpenSettingsPanel(void);

NS_ASSUME_NONNULL_END
