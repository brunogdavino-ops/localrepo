#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const admin = require('../functions/node_modules/firebase-admin');

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      continue;
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    i += 1;
  }
  return args;
}

function requireArg(args, key) {
  const value = args[key];
  if (!value || typeof value !== 'string') {
    throw new Error(`Missing required argument --${key}`);
  }
  return value;
}

function parseCsv(csvText) {
  const normalized = csvText.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
  const lines = normalized.split('\n').filter((line) => line.trim().length > 0);
  if (lines.length < 2) {
    throw new Error('CSV vazio ou sem linhas de dados.');
  }

  const header = lines[0].split(';').map((item) => item.trim());
  const expectedHeader = ['category_name', 'question_order', 'question_name', 'weight'];
  if (header.length !== expectedHeader.length || !header.every((value, index) => value === expectedHeader[index])) {
    throw new Error(`Header inesperado no CSV. Esperado: ${expectedHeader.join(';')}. Recebido: ${header.join(';')}`);
  }

  return lines.slice(1).map((line, index) => {
    const parts = line.split(';');
    if (parts.length !== 4) {
      throw new Error(`Linha ${index + 2} invalida no CSV: ${line}`);
    }

    const categoryName = parts[0].trim();
    const orderRaw = parts[1].trim();
    const questionName = parts[2].trim();
    const weightRaw = parts[3].trim();

    const order = Number.parseInt(orderRaw, 10);
    const weight = Number.parseInt(weightRaw, 10);

    if (!categoryName) {
      throw new Error(`Linha ${index + 2} com categoria vazia.`);
    }
    if (!questionName) {
      throw new Error(`Linha ${index + 2} com pergunta vazia.`);
    }
    if (!Number.isFinite(order)) {
      throw new Error(`Linha ${index + 2} com question_order invalido: ${orderRaw}`);
    }
    if (!Number.isFinite(weight)) {
      throw new Error(`Linha ${index + 2} com weight invalido: ${weightRaw}`);
    }

    return {
      categoryName,
      order,
      questionName,
      weight,
    };
  });
}

function normalizeName(value) {
  return value.trim().replace(/\s+/g, ' ');
}

function buildVersionedTemplateName(baseName, version) {
  const trimmed = baseName.trim();
  if (/\bv\d+$/i.test(trimmed)) {
    return trimmed.replace(/\bv\d+$/i, `v${version}`);
  }
  return `${trimmed} v${version}`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const csvPath = path.resolve(requireArg(args, 'csv'));
  const serviceAccountPath = path.resolve(requireArg(args, 'serviceAccount'));
  const sourceVersion = Number.parseInt(args.sourceVersion ?? '1', 10);
  const targetVersion = Number.parseInt(args.targetVersion ?? '2', 10);

  if (!Number.isFinite(sourceVersion) || !Number.isFinite(targetVersion)) {
    throw new Error('sourceVersion/targetVersion invalidos.');
  }
  if (sourceVersion === targetVersion) {
    throw new Error('sourceVersion e targetVersion nao podem ser iguais.');
  }

  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const db = admin.firestore();
  const csvRows = parseCsv(fs.readFileSync(csvPath, 'utf8'));

  const sourceTemplateSnapshot = await db
    .collection('templates')
    .where('version', '==', sourceVersion)
    .limit(1)
    .get();

  if (sourceTemplateSnapshot.empty) {
    throw new Error(`Template v${sourceVersion} nao encontrado.`);
  }

  const existingTargetSnapshot = await db
    .collection('templates')
    .where('version', '==', targetVersion)
    .limit(1)
    .get();

  if (!existingTargetSnapshot.empty) {
    throw new Error(`Ja existe template v${targetVersion}: ${existingTargetSnapshot.docs[0].id}`);
  }

  const sourceTemplateDoc = sourceTemplateSnapshot.docs[0];
  const sourceTemplateData = sourceTemplateDoc.data();
  const sourceTemplateRef = sourceTemplateDoc.ref;

  const categorySnapshot = await db
    .collection('categories')
    .where('templateref', '==', sourceTemplateRef)
    .orderBy('order')
    .get();

  if (categorySnapshot.empty) {
    throw new Error(`Nenhuma categoria encontrada para o template v${sourceVersion}.`);
  }

  const sourceCategories = categorySnapshot.docs.map((doc) => ({
    id: doc.id,
    ref: doc.ref,
    data: doc.data(),
    normalizedName: normalizeName(String(doc.data().name ?? '')),
  }));

  const sourceCategoryByName = new Map();
  for (const category of sourceCategories) {
    if (!category.normalizedName) {
      throw new Error(`Categoria ${category.id} do v${sourceVersion} esta sem nome.`);
    }
    if (sourceCategoryByName.has(category.normalizedName)) {
      throw new Error(`Categoria duplicada no v${sourceVersion}: ${category.normalizedName}`);
    }
    sourceCategoryByName.set(category.normalizedName, category);
  }

  const csvCategoryNames = [...new Set(csvRows.map((row) => normalizeName(row.categoryName)))];
  const unknownCategories = csvCategoryNames.filter((name) => !sourceCategoryByName.has(name));
  if (unknownCategories.length > 0) {
    throw new Error(`Categorias do CSV nao encontradas no v${sourceVersion}: ${unknownCategories.join(', ')}`);
  }

  const newTemplateRef = db.collection('templates').doc();
  const companyReference = sourceTemplateData.reference ?? null;
  const newTemplateData = {
    ...sourceTemplateData,
    string: buildVersionedTemplateName(String(sourceTemplateData.string ?? 'Template'), targetVersion),
    version: targetVersion,
    is_active: false,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  const batch = db.batch();
  batch.set(newTemplateRef, newTemplateData);

  const newCategoryByName = new Map();
  for (const sourceCategory of sourceCategories) {
    const newCategoryRef = db.collection('categories').doc();
    const newCategoryData = {
      ...sourceCategory.data,
      templateref: newTemplateRef,
    };
    batch.set(newCategoryRef, newCategoryData);
    newCategoryByName.set(sourceCategory.normalizedName, newCategoryRef);
  }

  for (const row of csvRows) {
    const normalizedCategoryName = normalizeName(row.categoryName);
    const categoryRef = newCategoryByName.get(normalizedCategoryName);
    if (!categoryRef) {
      throw new Error(`Categoria sem mapeamento no v${targetVersion}: ${row.categoryName}`);
    }

    const newQuestionRef = db.collection('questions').doc();
    batch.set(newQuestionRef, {
      text: row.questionName,
      weight: row.weight,
      order: row.order,
      templateRef: newTemplateRef,
      categoryRef,
      companyRef: companyReference,
      active: true,
    });
  }

  await batch.commit();

  console.log(JSON.stringify({
    sourceTemplateId: sourceTemplateDoc.id,
    newTemplateId: newTemplateRef.id,
    templatesCreated: 1,
    categoriesCreated: sourceCategories.length,
    questionsCreated: csvRows.length,
    targetVersion,
    templateName: newTemplateData.string,
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
