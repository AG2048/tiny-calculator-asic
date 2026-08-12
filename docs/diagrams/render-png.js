const path = require("path");
const sharp = require("sharp");

const diagrams = [
  "architecture",
  "button-array",
  "fsm-simplified",
  "fsm-detailed",
];

async function render() {
  for (const name of diagrams) {
    const source = path.join(__dirname, `${name}.svg`);
    const destination = path.join(__dirname, `${name}.png`);
    await sharp(source).png({
      compressionLevel: 9,
      palette: true,
      colours: 256,
      dither: 0,
    }).toFile(destination);
    console.log(`Wrote ${name}.png`);
  }
}

render().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
