import UAParser from "ua-parser-js";

export default {
  mounted() {
    const UA = navigator.userAgent;
    let parser = new UAParser(UA);

    this.handleEvent("screen", () => {
      this.pushEvent("page-size", {
        screenWidth: window.innerWidth,
        screenHeight: window.innerHeight,
      });
    });

    window.addEventListener("resize", () => {
      alert("resize");
      console.log("resize");
      this.pushEvent("page-size", {
        screenWidth: window.innerWidth,
        screenHeight: window.innerHeight,
        // userAgent: UA,
        // device: parser.getDevice(),
        // trigger: "load",
      });
    });
  },
};
