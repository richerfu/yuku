struct GenericStruct<T> {
  value: T;
  get(): T {
    return this.value;
  }
}
