import lazy { Helper } from './Helper';
import { Base } from './Base';

@Builder
function MyCard(title: string, count: number) {
  Column() {
    Text(title)
    Text(`count: ${count}`)
  }
}

@Entry
@Component
struct Home {
  @State count: number = 0;
  @Local message: string = 'Hello';
  private data: string[] = [];

  aboutToAppear(): void {}

  build() {
    Column() {
      MyCard(this.message, this.count)
      Text(this.message)
        .fontSize(16)
        .fontColor('#333')
      Button('Click me')
        .onClick(() => {
          this.count += 1;
        })
      if (this.count > 0) {
        Text(`Clicked ${this.count} times`)
      }
    }
    .width('100%')
    .height('100%')
    .animation({
      normal: { .backgroundColor('#ffffeef0').borderWidth(1) }
      , disabled: { .opacity(0.3) }
    })
  }

  get double(): number {
    return this.count * 2;
  }
}

@interface MyAnnotation {
  value: string;
  count?: number = 0;
}
