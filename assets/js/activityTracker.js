const ActivityTracker = {
  mounted() {
    let pushActivity = (() => {
      let active = true;
      //   delay 1 min
      const delay = 10 * 60 * 1000;
      console.log({ active });

      return () => {
        if (active) {
          active = false;

          setTimeout(() => {
            active = true;

            this.pushEventTo("#" + this.el.id, "inactivity");
          }, delay);
        }
      };
    })();

    pushActivity();
    window.addEventListener("mousemove", pushActivity);
    window.addEventListener("scroll", pushActivity);
    window.addEventListener("keydown", pushActivity);
    window.addEventListener("resize", pushActivity);
  },
};

export default ActivityTracker;
