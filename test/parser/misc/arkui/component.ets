@Component
struct Greeter {
  @State name: string = 'World';
  build() {
    Column() {
      Text('Hello')
      Button('click').onClick(() => {
        this.name = 'ArkUI';
      })
    }
  }
}
