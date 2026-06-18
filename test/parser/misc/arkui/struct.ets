@Component
struct MyComponent {
  @State count: number = 0;
  @Local message: string = 'Hello';
  private label: string = 'lbl';
  build() {}
  inc(): void {
    this.count += 1;
  }
  get double(): number {
    return this.count * 2;
  }
  set double(value: number) {
    this.count = value / 2;
  }
}
