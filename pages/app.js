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
  const downloadLink = document.querySelector("#download-link");
  let downloadUrl = null;

  const cleanTarget = value => value.trim();
  const appIdFor = target => `org.scummvm.launcher.${target.toLowerCase().replace(/_/g, "-")}`;
  const normalizeTarName = name => name.replace(/^\.\//, "").replace(/^\//, "");

  targetInput.addEventListener("input", () => {
    const target = cleanTarget(targetInput.value);
    appIdOutput.value = target ? appIdFor(target) : "org.scummvm.launcher.…";
  });

  window.addEventListener("beforeunload", () => {
    if (downloadUrl) URL.revokeObjectURL(downloadUrl);
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
    if (decoder.decode(bytes.slice(0, 8)) !== "!<arch>\n") {
      throw new Error("Ungültige IPK-Datei");
    }

    const entries = [];
    let offset = 8;
    while (offset + 60 <= bytes.length) {
      const header = decoder.decode(bytes.slice(offset, offset + 60));
      const name = header.slice(0, 16).trim().replace(/\/$/, "");
      const size = Number.parseInt(header.slice(48, 58).trim(), 10);
      const start = offset + 60;
      const end = start + size;

      if (!name || !Number.isFinite(size) || size < 0 || end > bytes.length) {
        throw new Error("Beschädigtes IPK-Archiv");
      }

      entries.push({ name, data: bytes.slice(start, end) });
      offset = end + (size % 2);
    }
    return entries;
  }

  function writeAr(entries) {
    const parts = [encoder.encode("!<arch>\n")];
    for (const entry of entries) {
      const fields = [
        `${entry.name}/`.padEnd(16),
        "0".padEnd(12),
        "0".padEnd(6),
        "0".padEnd(6),
        "100644".padEnd(8),
        String(entry.data.length).padEnd(10),
        "`\n"
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
      const end = start + size;

      if (!Number.isFinite(size) || size < 0 || end > bytes.length) {
        throw new Error("Beschädigtes TAR-Archiv im Template");
      }

      entries.push({
        name: fullName,
        type,
        mode: readString(header, 100, 8) || "0000644",
        data: bytes.slice(start, end)
      });
      offset = start + align(size, 512);
    }
    return entries;
  }

  function octal(value, length) {
    return `${value.toString(8).padStart(length - 1, "0")}\0`;
  }

  function writeTar(entries) {
    const parts = [];
    const timestamp = Math.floor(Date.now() / 1000);

    for (const entry of entries) {
      const header = new Uint8Array(512);
      const name = encoder.encode(entry.name.replace(/^\.\//, ""));
      if (name.length > 100) {
        throw new Error(`Dateiname im Template ist zu lang: ${entry.name}`);
      }

      header.set(name, 0);
      header.set(encoder.encode((entry.mode || "0000644").padStart(7, "0") + "\0"), 100);
      header.set(encoder.encode(octal(0, 8)), 108);
      header.set(encoder.encode(octal(0, 8)), 116);
      header.set(encoder.encode(octal(entry.data.length, 12)), 124);
      header.set(encoder.encode(octal(timestamp, 12)), 136);
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

  function findTarEntry(entries, name) {
    const normalized = normalizeTarName(name);
    return entries.find(entry => normalizeTarName(entry.name) === normalized);
  }

  function replaceTarEntry(entries, name, data) {
    const entry = findTarEntry(entries, name);
    if (entry) {
      entry.data = data;
      return;
    }
    entries.push({ name, type: "0", mode: "0000644", data });
  }

  function locateTemplateApp(dataEntries) {
    const appInfoEntry = dataEntries.find(entry =>
      normalizeTarName(entry.name) === "appinfo.json" ||
      normalizeTarName(entry.name).endsWith("/appinfo.json")
    );
    if (!appInfoEntry) throw new Error("appinfo.json fehlt im Template");

    let appInfo;
    try {
      appInfo = JSON.parse(decoder.decode(appInfoEntry.data));
    } catch {
      throw new Error("appinfo.json im Template ist ungültig");
    }
    if (!appInfo.id) throw new Error("Template-App besitzt keine App-ID");

    const suffix = "appinfo.json";
    const root = appInfoEntry.name
      .slice(0, appInfoEntry.name.length - suffix.length)
      .replace(/\/$/, "");
    return { appInfo, root };
  }

  function renameAppRoot(entries, oldRoot, oldId, newId) {
    if (!oldRoot) return oldRoot;
    const newRoot = oldRoot.includes(oldId) ? oldRoot.replace(oldId, newId) : oldRoot;
    if (newRoot === oldRoot) return oldRoot;

    for (const entry of entries) {
      if (entry.name === oldRoot || entry.name.startsWith(`${oldRoot}/`)) {
        entry.name = `${newRoot}${entry.name.slice(oldRoot.length)}`;
      }
    }
    return newRoot;
  }

  function appPath(root, filename) {
    return root ? `${root}/${filename}` : filename;
  }

  async function iconPng(file) {
    const imageUrl = URL.createObjectURL(file);
    try {
      const image = new Image();
      image.decoding = "async";
      await new Promise((resolve, reject) => {
        image.onload = resolve;
        image.onerror = () => reject(new Error("Das Icon konnte nicht gelesen werden"));
        image.src = imageUrl;
      });

      const canvas = document.createElement("canvas");
      canvas.width = 160;
      canvas.height = 160;
      const context = canvas.getContext("2d");
      if (!context) throw new Error("Canvas wird vom Browser nicht unterstützt");

      context.clearRect(0, 0, 160, 160);
      const scale = Math.min(160 / image.naturalWidth, 160 / image.naturalHeight);
      const width = image.naturalWidth * scale;
      const height = image.naturalHeight * scale;
      context.drawImage(image, (160 - width) / 2, (160 - height) / 2, width, height);

      const blob = await new Promise((resolve, reject) => {
        canvas.toBlob(result => {
          if (result) resolve(result);
          else reject(new Error("Das Icon konnte nicht in PNG umgewandelt werden"));
        }, "image/png");
      });
      return new Uint8Array(await blob.arrayBuffer());
    } finally {
      URL.revokeObjectURL(imageUrl);
    }
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
      text = pattern.test(text)
        ? text.replace(pattern, `${key}: ${value}`)
        : `${text.trimEnd()}\n${key}: ${value}\n`;
    }
    return text;
  }

  function offerDownload(ipk, filename) {
    if (downloadUrl) URL.revokeObjectURL(downloadUrl);
    downloadUrl = URL.createObjectURL(new Blob([ipk], { type: "application/octet-stream" }));
    downloadLink.href = downloadUrl;
    downloadLink.download = filename;
    downloadLink.textContent = `${filename} herunterladen`;
    downloadLink.hidden = false;

    // Works in most browsers. Safari may block an automatic download after
    // asynchronous processing; the visible link remains available as fallback.
    downloadLink.click();
  }

  form.addEventListener("submit", async event => {
    event.preventDefault();
    status.className = "";
    status.textContent = "";
    downloadLink.hidden = true;
    button.disabled = true;

    try {
      if (!window.fflate) throw new Error("Archivbibliothek konnte nicht geladen werden");

      const target = cleanTarget(targetInput.value);
      const title = titleInput.value.trim();
      const icon = iconInput.files[0];
      if (!/^[A-Za-z0-9_-]+$/.test(target)) throw new Error("Ungültige Target-ID");
      if (!title) throw new Error("Ein Titel ist erforderlich");
      if (!icon) throw new Error("Ein Icon ist erforderlich");

      status.textContent = "Template wird geladen …";
      const templateResponse = await fetch("template.ipk", { cache: "no-store" });
      if (!templateResponse.ok) throw new Error("template.ipk konnte nicht geladen werden");

      const arEntries = parseAr(new Uint8Array(await templateResponse.arrayBuffer()));
      const dataArchive = arEntries.find(entry => entry.name === "data.tar.gz");
      const controlArchive = arEntries.find(entry => entry.name === "control.tar.gz");
      if (!dataArchive || !controlArchive) throw new Error("Nicht unterstütztes Template-Format");

      status.textContent = "Starter wird erstellt …";
      const { gunzipSync, gzipSync } = window.fflate;
      const dataEntries = parseTar(gunzipSync(dataArchive.data));
      const controlEntries = parseTar(gunzipSync(controlArchive.data));
      const packageId = appIdFor(target);
      const template = locateTemplateApp(dataEntries);
      const appRoot = renameAppRoot(dataEntries, template.root, template.appInfo.id, packageId);

      const appInfo = {
        ...template.appInfo,
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

      replaceTarEntry(
        dataEntries,
        appPath(appRoot, "appinfo.json"),
        encoder.encode(`${JSON.stringify(appInfo, null, 2)}\n`)
      );
      replaceTarEntry(
        dataEntries,
        appPath(appRoot, "launcher.js"),
        encoder.encode(`(function(){"use strict";var b=new PalmServiceBridge();b.onservicecallback=function(){window.close();};b.call("luna://com.webos.applicationManager/launch",JSON.stringify({id:"org.scummvm.scummvm",params:{target:${JSON.stringify(target)}}}));setTimeout(function(){window.close();},3000);}());\n`)
      );
      replaceTarEntry(dataEntries, appPath(appRoot, "icon.png"), await iconPng(icon));

      const control = findTarEntry(controlEntries, "control");
      if (!control) throw new Error("control-Datei fehlt im Template");
      control.data = encoder.encode(patchControl(decoder.decode(control.data), packageId, title));

      for (let index = controlEntries.length - 1; index >= 0; index -= 1) {
        if (normalizeTarName(controlEntries[index].name) === "md5sums") {
          controlEntries.splice(index, 1);
        }
      }

      dataArchive.data = gzipSync(writeTar(dataEntries), { level: 9 });
      controlArchive.data = gzipSync(writeTar(controlEntries), { level: 9 });
      const ipk = writeAr(arEntries);
      const filename = `${packageId}_1.0.0_all.ipk`;
      offerDownload(ipk, filename);
      status.textContent = "IPK wurde erstellt. Falls der Download nicht automatisch startet, den Download-Link anklicken.";
    } catch (error) {
      console.error(error);
      status.textContent = error instanceof Error ? error.message : String(error);
      status.className = "error";
    } finally {
      button.disabled = false;
    }
  });
})();
