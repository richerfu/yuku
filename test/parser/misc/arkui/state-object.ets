@Component
struct Anim {
  @State color: string = '#fff';
  build() {
    Column() {
      Text('hi')
    }
    .animation({
      normal: { .backgroundColor('#ffffeef0').borderWidth(1) }
      , disabled: { .opacity(0.3) }
    })
  }
}
