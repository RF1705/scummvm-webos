(() => {
  "use strict";

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const form = document.querySelector("#generator");
  const targetInput = document.querySelector("#target");
  const titleInput = document.querySelector("#title");
  const iconInput = document.querySelector("#icon");
  const appIdOutput = document.querySelector("#app-id");
  const status = document.querySelector("#status");
  const button = form.querySelector("button");

  const cleanTarget = value => value.trim();
  const appIdFor = target => `org.scummvm.launcher.${target.toLowerCase().replace(/_/g, "-")}`;

  targetInput.addEventListener("input", () => {
    const target = cleanTarget(targetInput.value);
    appIdOutput.value = target ? appIdFor(target) : "org.scummvm.launcher.…";
  });

  function align(value, size) {
    return Math.ceil(value / size) * size;
  }

  function concat(parts) {
    const length = parts.reduce((sum, part) => sum + part.length, 0);
    const result = new Uint8Array(length);
    let offset = 0;
    for (const part of parts) {
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  }

  function parseAr(bytes) {
    if (decoder.decode(bytes.slice(0, 8)) !== "!<arch>\n") throw new Error("Ungültige IPK-Datei");
    const entries = [];
    let offset = 8;
    while (offset + 60 <= bytes.length) {
      const header = decoder.decode(bytes.slice(offset, offset + 60));
      const name = header.slice(0, 16).trim().replace(/\/$/, "");
      const size = Number.parseInt(header.slice(48, 58).trim(), 10);
      if (!name || !Number.isFinite(size)) break;
      const start = offset + 60;
      entries.push({ name, data: bytes.slice(start, start + size) });
      offset = start + size + (size % 2);
    }
    return entries;
  }

  function writeAr(entries) {
    const parts = [encoder.encode("!<arch>\n")];
    for (const entry of entries) {
      const fields = [
        `${entry.name}/`.padEnd(16),
        "0".padEnd(12), "0".padEnd(6), "0".padEnd(6),
        "100644".padEnd(8), String(entry.data.length).padEnd(10), "`\n"
      ];
      parts.push(encoder.encode(fields.join("")), entry.data);
      if (entry.data.length % 2) parts.push(new Uint8Array([10]));
    }
    return concat(parts);
  }

  function readString(block, start, length) {
    return decoder.decode(block.slice(start, start + length)).replace(/\0.*$/, "").trim();
  }

  function parseTar(bytes) {
    const entries = [];
    for (let offset = 0; offset + 512 <= bytes.length;) {
      const header = bytes.slice(offset, offset + 512);
      if (header.every(value => value === 0)) break;
      const name = readString(header, 0, 100);
      const prefix = readString(header, 345, 155);
      const size = Number.parseInt(readString(header, 124, 12) || "0", 8);
      const type = String.fromCharCode(header[156] || 48);
      const fullName = prefix ? `${prefix}/${name}` : name;
      const start = offset + 512;
      entries.push({ name: fullName, type, mode: readString(header, 100, 8) || "0000644", data: bytes.slice(start, start + size) });
      offset = start + align(size, 512);
    }
    return entries;
  }

  function octal(value, length) {
    return `${value.toString(8).padStart(length - 1, "0")}\0`;
  }

  function writeTar(entries) {
    const parts = [];
    for (const entry of entries) {
      const header = new Uint8Array(512);
      const name = encoder.encode(entry.name.replace(/^\.\//, ""));
      if (name.length > 100) throw new Error(`Dateiname im Template ist zu lang: ${entry.name}`);
      header.set(name, 0);
      header.set(encoder.encode((entry.mode || "0000644").padStart(7, "0") + "\0"), 100);
      header.set(encoder.encode(octal(0, 8)), 108);
      header.set(encoder.encode(octal(0, 8)), 116);
      header.set(encoder.encode(octal(entry.data.length, 12)), 124);
      header.set(encoder.encode(octal(Math.floor(Date.now() / 1000), 12)), 136);
      header.fill(32, 148, 156);
      header[156] = (entry.type || "0").charCodeAt(0);
      header.set(encoder.encode("ustar\0"), 257);
      header.set(encoder.encode("00"), 263);
      const checksum = header.reduce((sum, value) => sum + value, 0);
      header.set(encoder.encode(`${checksum.toString(8).padStart(6, "0")}\0 `), 148);
      parts.push(header, entry.data);
      const padding = align(entry.data.length, 512) - entry.data.length;
      if (padding) parts.push(new Uint8Array(padding));
    }
    parts.push(new Uint8Array(1024));
    return concat(parts);
  }

  function replaceTarEntry(entries, name, data) {
    const candidates = [name, `./${name}`];
    const entry = entries.find(item => candidates.includes(item.name));
    if (entry) entry.data = data;
    else entries.push({ name, type: "0", mode: "0000644", data });
  }

  async function iconPng(file) {
    const image = await createImageBitmap(file);
    const canvas = document.createElement("canvas");
    canvas.width = 160;
    canvas.height = 160;
    const context = canvas.getContext("2d");
    context.clearRect(0, 0, 160, 160);
    const scale = Math.min(160 / image.width, 160 / image.height);
    const width = image.width * scale;
    const height = image.height * scale;
    context.drawImage(image, (160 - width) / 2, (160 - height) / 2, width, height);
    const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"));
    image.close();
    return new Uint8Array(await blob.arrayBuffer());
  }

  function patchControl(text, packageId, title) {
    const values = {
      Package: packageId,
      Version: "1.0.0",
      Architecture: "all",
      Description: `ScummVM launcher for ${title}`
    };
    for (const [key, value] of Object.entries(values)) {
      const pattern = new RegExp(`^${key}:.*$`, "m");
      text = pattern.test(text) ? text.replace(pattern, `${key}: ${value}`) : `${text.trimEnd()}\n${key}: ${value}\n`;
    }
    return text;
  }

  form.addEventListener("submit", async event => {
    event.preventDefault();
    status.className = "";
    button.disabled = true;
    try {
      if (!window.fflate) throw new Error("Archivbibliothek konnte nicht geladen werden");
      const target = cleanTarget(targetInput.value);
      const title = titleInput.value.trim();
      if (!/^[A-Za-z0-9_-]+$/.test(target)) throw new Error("Ungültige Target-ID");
      if (!title) throw new Error("Ein Titel ist erforderlich");
      if (!iconInput.files[0]) throw new Error("Ein Icon ist erforderlich");

      status.textContent = "Template wird geladen …";
      const templateResponse = await fetch("template.ipk", { cache: "no-store" });
      if (!templateResponse.ok) throw new Error("template.ipk konnte nicht geladen werden");
      const arEntries = parseAr(new Uint8Array(await templateResponse.arrayBuffer()));
      const dataArchive = arEntries.find(entry => /^data\.tar\.(gz|zst|xz)$/.test(entry.name));
      const controlArchive = arEntries.find(entry => /^control\.tar\.gz$/.test(entry.name));
      if (!dataArchive || !controlArchive || !dataArchive.name.endsWith(".gz")) throw new Error("Nicht unterstütztes Template-Format");

      status.textContent = "Starter wird erstellt …";
      const dataEntries = parseTar(fflate.gunzipSync(dataArchive.data));
      const controlEntries = parseTar(fflate.gunzipSync(controlArchive.data));
      const packageId = appIdFor(target);
      const appInfo = {
        id: packageId,
        version: "1.0.0",
        vendor: "RF1705",
        type: "web",
        main: "index.html",
        title,
        icon: "icon.png",
        largeIcon: "icon.png",
        appDescription: `Launches ${title} in ScummVM`,
        noSplashOnLaunch: true,
        transparent: true
      };
      replaceTarEntry(dataEntries, "appinfo.json", encoder.encode(`${JSON.stringify(appInfo, null, 2)}\n`));
      replaceTarEntry(dataEntries, "launcher.js", encoder.encode(`(function(){"use strict";var b=new PalmServiceBridge();b.onservicecallback=function(){window.close();};b.call("luna://com.webos.applicationManager/launch",JSON.stringify({id:"org.scummvm.scummvm",params:{target:${JSON.stringify(target)}}}));setTimeout(function(){window.close();},3000);}());\n`));
      replaceTarEntry(dataEntries, "icon.png", await iconPng(iconInput.files[0]));

      const control = controlEntries.find(entry => ["control", "./control"].includes(entry.name));
      if (!control) throw new Error("control-Datei fehlt im Template");
      control.data = encoder.encode(patchControl(decoder.decode(control.data), packageId, title));
      const md5sums = controlEntries.find(entry => ["md5sums", "./md5sums"].includes(entry.name));
      if (md5sums) md5sums.data = new Uint8Array();

      dataArchive.data = fflate.gzipSync(writeTar(dataEntries), { level: 9 });
      controlArchive.data = fflate.gzipSync(writeTar(controlEntries), { level: 9 });
      const ipk = writeAr(arEntries);
      const blob = new Blob([ipk], { type: "application/vnd.webos.ipk" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `${packageId}_1.0.0_all.ipk`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      status.textContent = "IPK wurde erstellt.";
    } catch (error) {
      console.error(error);
      status.textContent = error instanceof Error ? error.message : String(error);
      status.className = "error";
    } finally {
      button.disabled = false;
    }
  });
}());
