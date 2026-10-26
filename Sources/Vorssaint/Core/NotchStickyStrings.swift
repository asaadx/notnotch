// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchStickyStrings {
    let title: String
    let empty: String
    let newNote: String
    let placeholder: String
    let delete: String
    let done: String
    let untitled: String
    /// One a colour, in `NotchStickyColor.allCases` order.
    let colorNames: [String]
    let limitFormat: String
    let loadFailed: String
    let saveFailed: String

    func name(of color: NotchStickyColor) -> String {
        let index = NotchStickyColor.allCases.firstIndex(of: color) ?? 0
        return colorNames.indices.contains(index) ? colorNames[index] : color.rawValue
    }
}

extension FeatureStrings {
    static func notchStickies(_ language: AppLanguage) -> NotchStickyStrings {
        switch language {
        case .enUS: return NotchStickyStrings(
            title: "Sticky Notes",
            empty: "Stick a thought here",
            newNote: "New Note",
            placeholder: "Write something…",
            delete: "Delete",
            done: "Done",
            untitled: "Note",
            colorNames: ["Sky", "Mint", "Lilac", "Lemon", "Rose", "Peach"],
            limitFormat: "Up to %d notes",
            loadFailed: "Sticky notes could not be read.",
            saveFailed: "Sticky notes could not be saved."
        )
        case .ptBR: return NotchStickyStrings(
            title: "Notas Adesivas",
            empty: "Cole uma ideia aqui",
            newNote: "Nova Nota",
            placeholder: "Escreva algo…",
            delete: "Apagar",
            done: "OK",
            untitled: "Nota",
            colorNames: ["Céu", "Menta", "Lilás", "Limão", "Rosa", "Pêssego"],
            limitFormat: "Até %d notas",
            loadFailed: "Não foi possível ler as notas adesivas.",
            saveFailed: "Não foi possível salvar as notas adesivas."
        )
        case .es: return NotchStickyStrings(
            title: "Notas Adhesivas",
            empty: "Pega una idea aquí",
            newNote: "Nueva Nota",
            placeholder: "Escribe algo…",
            delete: "Eliminar",
            done: "Listo",
            untitled: "Nota",
            colorNames: ["Cielo", "Menta", "Lila", "Limón", "Rosa", "Melocotón"],
            limitFormat: "Hasta %d notas",
            loadFailed: "No se pudieron leer las notas adhesivas.",
            saveFailed: "No se pudieron guardar las notas adhesivas."
        )
        case .sk: return NotchStickyStrings(
            title: "Lepiace poznámky",
            empty: "Prilepte sem myšlienku",
            newNote: "Nová poznámka",
            placeholder: "Napíšte niečo…",
            delete: "Vymazať",
            done: "Hotovo",
            untitled: "Poznámka",
            colorNames: ["Obloha", "Mäta", "Orgován", "Citrón", "Ruža", "Broskyňa"],
            limitFormat: "Najviac %d poznámok",
            loadFailed: "Lepiace poznámky sa nepodarilo načítať.",
            saveFailed: "Lepiace poznámky sa nepodarilo uložiť."
        )
        case .de: return NotchStickyStrings(
            title: "Haftnotizen",
            empty: "Kleb hier einen Gedanken hin",
            newNote: "Neue Notiz",
            placeholder: "Schreib etwas …",
            delete: "Löschen",
            done: "Fertig",
            untitled: "Notiz",
            colorNames: ["Himmel", "Minze", "Flieder", "Zitrone", "Rose", "Pfirsich"],
            limitFormat: "Bis zu %d Notizen",
            loadFailed: "Die Haftnotizen konnten nicht gelesen werden.",
            saveFailed: "Die Haftnotizen konnten nicht gesichert werden."
        )
        case .fr: return NotchStickyStrings(
            title: "Post-it",
            empty: "Collez une idée ici",
            newNote: "Nouvelle note",
            placeholder: "Écrivez quelque chose…",
            delete: "Supprimer",
            done: "OK",
            untitled: "Note",
            colorNames: ["Ciel", "Menthe", "Lilas", "Citron", "Rose", "Pêche"],
            limitFormat: "Jusqu’à %d notes",
            loadFailed: "Les notes n’ont pas pu être lues.",
            saveFailed: "Les notes n’ont pas pu être enregistrées."
        )
        case .it: return NotchStickyStrings(
            title: "Note adesive",
            empty: "Attacca qui un pensiero",
            newNote: "Nuova nota",
            placeholder: "Scrivi qualcosa…",
            delete: "Elimina",
            done: "Fine",
            untitled: "Nota",
            colorNames: ["Cielo", "Menta", "Lilla", "Limone", "Rosa", "Pesca"],
            limitFormat: "Fino a %d note",
            loadFailed: "Impossibile leggere le note adesive.",
            saveFailed: "Impossibile salvare le note adesive."
        )
        case .ru: return NotchStickyStrings(
            title: "Стикеры",
            empty: "Приклейте сюда мысль",
            newNote: "Новый стикер",
            placeholder: "Напишите что-нибудь…",
            delete: "Удалить",
            done: "Готово",
            untitled: "Стикер",
            colorNames: ["Небо", "Мята", "Сирень", "Лимон", "Роза", "Персик"],
            limitFormat: "Не больше %d стикеров",
            loadFailed: "Не удалось прочитать стикеры.",
            saveFailed: "Не удалось сохранить стикеры."
        )
        case .tr: return NotchStickyStrings(
            title: "Yapışkan Notlar",
            empty: "Buraya bir düşünce yapıştırın",
            newNote: "Yeni Not",
            placeholder: "Bir şey yazın…",
            delete: "Sil",
            done: "Bitti",
            untitled: "Not",
            colorNames: ["Gök", "Nane", "Leylak", "Limon", "Gül", "Şeftali"],
            limitFormat: "En fazla %d not",
            loadFailed: "Yapışkan notlar okunamadı.",
            saveFailed: "Yapışkan notlar kaydedilemedi."
        )
        case .ja: return NotchStickyStrings(
            title: "付箋",
            empty: "思いついたことを貼っておこう",
            newNote: "新規付箋",
            placeholder: "何か書く…",
            delete: "削除",
            done: "完了",
            untitled: "付箋",
            colorNames: ["スカイ", "ミント", "ライラック", "レモン", "ローズ", "ピーチ"],
            limitFormat: "最大%d枚",
            loadFailed: "付箋を読み込めませんでした。",
            saveFailed: "付箋を保存できませんでした。"
        )
        case .ko: return NotchStickyStrings(
            title: "스티커 메모",
            empty: "떠오른 생각을 여기 붙여 두세요",
            newNote: "새로운 메모",
            placeholder: "무언가 쓰기…",
            delete: "삭제",
            done: "완료",
            untitled: "메모",
            colorNames: ["스카이", "민트", "라일락", "레몬", "로즈", "피치"],
            limitFormat: "최대 %d개",
            loadFailed: "스티커 메모를 읽을 수 없습니다.",
            saveFailed: "스티커 메모를 저장할 수 없습니다."
        )
        case .uk: return NotchStickyStrings(
            title: "Стікери",
            empty: "Приліпіть сюди думку",
            newNote: "Новий стікер",
            placeholder: "Напишіть щось…",
            delete: "Видалити",
            done: "Готово",
            untitled: "Стікер",
            colorNames: ["Небо", "М’ята", "Бузок", "Лимон", "Троянда", "Персик"],
            limitFormat: "Не більше %d стікерів",
            loadFailed: "Не вдалося прочитати стікери.",
            saveFailed: "Не вдалося зберегти стікери."
        )
        case .zhHans: return NotchStickyStrings(
            title: "便签",
            empty: "在这里贴上一个想法",
            newNote: "新建便签",
            placeholder: "写点什么…",
            delete: "删除",
            done: "完成",
            untitled: "便签",
            colorNames: ["天空", "薄荷", "丁香", "柠檬", "玫瑰", "蜜桃"],
            limitFormat: "最多 %d 张",
            loadFailed: "无法读取便签。",
            saveFailed: "无法保存便签。"
        )
        case .zhTW: return NotchStickyStrings(
            title: "便條紙",
            empty: "在這裡貼上一個想法",
            newNote: "新增便條",
            placeholder: "寫點什麼…",
            delete: "刪除",
            done: "完成",
            untitled: "便條",
            colorNames: ["天空", "薄荷", "丁香", "檸檬", "玫瑰", "蜜桃"],
            limitFormat: "最多 %d 張",
            loadFailed: "無法讀取便條紙。",
            saveFailed: "無法儲存便條紙。"
        )
        case .zhHK: return NotchStickyStrings(
            title: "便條紙",
            empty: "在這裡貼上一個想法",
            newNote: "新增便條",
            placeholder: "寫點甚麼…",
            delete: "刪除",
            done: "完成",
            untitled: "便條",
            colorNames: ["天空", "薄荷", "丁香", "檸檬", "玫瑰", "蜜桃"],
            limitFormat: "最多 %d 張",
            loadFailed: "無法讀取便條紙。",
            saveFailed: "無法儲存便條紙。"
        )
        }
    }
}
