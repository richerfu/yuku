@Component
export declare struct v3 {
  authPageController: w3 | null;
  private controller;
  private url;
  @State progress: number;
  private hasBack;
  aboutToAppear(): void;
  aboutToDisappear(): void;
  build(): void;
  parseAuthResult(url: string): boolean;
  cancel(): void;
  back: (p: w3) => void;
}
