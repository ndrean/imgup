import UAParser from "ua-parser-js";

export default {
  mounted() {
    const UA = navigator.userAgent;
    let parser = new UAParser(UA);

    // If you want to listen on resize and push the same event
    window.addEventListener("resize", () => {
      console.log(parser.getResult());
      this.pushEvent("page-size", {
        screenWidth: window.innerWidth,
        screenHeight: window.innerHeight,
        userAgent: UA,
        device: parser.getDevice(),
        trigger: "resize",
      });
    });

    // window.addEventListener("load", () => {
    //   this.pushEvent("page-size", {
    //     screenWidth: window.innerWidth,
    //     screenHeight: window.innerHeight,
    //     userAgent: UA,
    //     device: parser.getDevice(),
    //     trigger: "load",
    //   });
    // });
  },
};
