@Component
struct Styled {
  build() {
    Column() {
      Text('hi').fontSize(12)
    }
  }
  applyStyle(): void {
    .backgroundColor('#ffffeef0').borderWidth(1)
  }
}
