@Builder
function MyCard(title: string, count: number) {
  Column() {
    Text(title)
    Text(`count: ${count}`)
  }
}

@LocalBuilder
function LocalHelper() {
  Text('helper')
}

@Component
struct Page {
  build() {
    Column() {
      MyCard('Hello', 1)
    }
  }
}
